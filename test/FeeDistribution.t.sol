// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "src/core/EventFactory.sol";
import "src/core/Event.sol";
import "src/core/TicketNFT.sol";
import "src/libraries/Constants.sol";
import "forge-std/console.sol";

// Mock IDRX token untuk testing
contract MockIDRX {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = 2; // IDRX memiliki 2 desimal
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        _transfer(sender, recipient, amount);
        
        // Jika allowance tidak terhingga (uint256 max value), jangan kurangi
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        }
        
        return true;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "Transfer from the zero address");
        require(recipient != address(0), "Transfer to the zero address");
        require(_balances[sender] >= amount, "Transfer amount exceeds balance");

        _balances[sender] -= amount;
        _balances[recipient] += amount;
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Approve from the zero address");
        require(spender != address(0), "Approve to the zero address");

        _allowances[owner][spender] = amount;
    }
}

contract FeeDistributionTest is Test {
    // Kontrak untuk testing
    EventFactory public factory;
    Event public eventContract;
    ITicketNFT public ticketNFT;
    MockIDRX public idrx;
    
    // Alamat untuk testing
    address public deployer;
    address public platformFeeReceiver;
    address public organizer;
    address public buyer;
    address public reseller;
    
    // Data event
    uint256 public eventDate;
    address public eventAddress;
    
    // Ticket prices and fees
    uint256 public constant TICKET_PRICE = 100 * 10**2; // 100 IDRX
    uint256 public constant RESALE_PRICE = 120 * 10**2; // 120 IDRX (20% markup)
    uint256 public constant PLATFORM_FEE_PERCENTAGE = Constants.PLATFORM_FEE_PERCENTAGE; // 100 basis points = 1%
    uint256 public constant ORGANIZER_FEE_PERCENTAGE = 250; // 250 basis points = 2.5%
    
    function setUp() public {
        console.log("Setting up FeeDistribution test environment");
        
        // Setup alamat untuk testing
        deployer = makeAddr("deployer");
        platformFeeReceiver = makeAddr("platformFeeReceiver");
        organizer = makeAddr("organizer");
        buyer = makeAddr("buyer");
        reseller = makeAddr("reseller");
        
        // Set tanggal event (30 hari di masa depan)
        eventDate = block.timestamp + 30 days;
        
        // Deploy kontrak sebagai deployer
        vm.startPrank(deployer);
        
        // Deploy token IDRX
        idrx = new MockIDRX("IDRX Token", "IDRX");
        
        // Deploy EventFactory
        factory = new EventFactory(address(idrx), address(0));
        
        // Set platform fee receiver
        factory.setPlatformFeeReceiver(platformFeeReceiver);
        
        vm.stopPrank();
        
        // Mint IDRX ke akun pengujian
        idrx.mint(buyer, 10000 * 10**2);
        idrx.mint(reseller, 10000 * 10**2);
        
        // Create Event directly untuk tes
        vm.startPrank(organizer);
        
        // 1. Deploy Event contract
        eventContract = new Event(address(0));
        
        // 2. Initialize Event
        eventContract.initialize(
            organizer,
            "Concert Event",
            "A live music concert",
            eventDate,
            "Jakarta Convention Center",
            "ipfs://QmTestMetadata"
        );
        
        // 3. Deploy TicketNFT
        TicketNFT ticketNFTContract = new TicketNFT(address(0));
        
        // 4. Initialize TicketNFT
        ticketNFTContract.initialize("Concert Event", "TIX", address(eventContract));
        
        // 5. Set TicketNFT in Event
        eventContract.setTicketNFT(address(ticketNFTContract), address(idrx), platformFeeReceiver);
        
        // 6. Tambahkan tier tiket
        eventContract.addTicketTier(
            "Regular",
            TICKET_PRICE,
            100, // 100 tiket tersedia
            4 // max 4 tiket per pembelian
        );
        
        // 7. Set resale rules
        eventContract.setResaleRules(
            2000, // 20% max markup
            ORGANIZER_FEE_PERCENTAGE, // 2.5% organizer fee
            false, // tidak ada batasan waktu resale
            1 // minimum 1 hari sebelum event
        );
        
        // Store alamat dan kontrak
        eventAddress = address(eventContract);
        ticketNFT = ITicketNFT(address(ticketNFTContract));
        
        vm.stopPrank();
        
        console.log("Event created at:", eventAddress);
        console.log("TicketNFT created at:", address(ticketNFT));
    }
    
    // Test distribusi fee untuk pembelian tiket primary
    function testPrimaryPurchaseFeeDistribution() public {
        console.log("=== STEP 1: Primary Purchase Fee Distribution Test ===");
        
        // Catat saldo awal
        uint256 initialOrganizerBalance = idrx.balanceOf(organizer);
        uint256 initialPlatformBalance = idrx.balanceOf(platformFeeReceiver);
        uint256 initialBuyerBalance = idrx.balanceOf(buyer);
        
        // Log saldo awal untuk debugging
        console.log("\n--- Initial Account Balances ---");
        console.log("Organizer address:", organizer);
        console.log("Platform receiver address:", platformFeeReceiver);
        console.log("Buyer address:", buyer);
        console.log("  Organizer balance:", initialOrganizerBalance);
        console.log("  Platform balance:", initialPlatformBalance);
        console.log("  Buyer balance:", initialBuyerBalance);
        
        // Log purchase details
        console.log("\n--- Purchase Details ---");
        console.log("Ticket price:", TICKET_PRICE);
        console.log("Quantity: 2");
        console.log("Total amount:", TICKET_PRICE * 2);
        console.log("Platform fee percentage (basis points):", PLATFORM_FEE_PERCENTAGE);
        
        // Beli 2 tiket sebagai buyer
        console.log("\n--- Executing Purchase ---");
        vm.startPrank(buyer);
        idrx.approve(eventAddress, TICKET_PRICE * 2);
        console.log("Approved amount:", TICKET_PRICE * 2);
        eventContract.purchaseTicket(0, 2);
        console.log("Purchase transaction completed");
        vm.stopPrank();
        
        // Hitung fee yang diharapkan
        uint256 totalPurchaseAmount = TICKET_PRICE * 2;
        uint256 expectedPlatformFee = (totalPurchaseAmount * PLATFORM_FEE_PERCENTAGE) / Constants.BASIS_POINTS;
        uint256 expectedOrganizerShare = totalPurchaseAmount - expectedPlatformFee;
        
        // Log pembayaran yang diharapkan
        console.log("\n--- Expected Fee Distribution ---");
        console.log("Total purchase amount:", totalPurchaseAmount);
        console.log("Expected platform fee:", expectedPlatformFee);
        console.log("Expected organizer share:", expectedOrganizerShare);
        console.log("Fee calculation: (amount * percentage) / basis_points");
        
        // Verifikasi distribusi fee
        uint256 actualPlatformFee = idrx.balanceOf(platformFeeReceiver) - initialPlatformBalance;
        uint256 actualOrganizerShare = idrx.balanceOf(organizer) - initialOrganizerBalance;
        uint256 buyerSpent = initialBuyerBalance - idrx.balanceOf(buyer);
        
        // Log distribusi aktual
        console.log("\n--- Actual Fee Distribution ---");
        console.log("Platform received:", actualPlatformFee);
        console.log("Organizer received:", actualOrganizerShare);
        console.log("Buyer spent:", buyerSpent);
        
        // Log final balances
        console.log("\n--- Final Account Balances ---");
        console.log("  Organizer balance:", idrx.balanceOf(organizer));
        console.log("  Platform balance:", idrx.balanceOf(platformFeeReceiver));
        console.log("  Buyer balance:", idrx.balanceOf(buyer));
        
        // Assertions
        assertEq(actualPlatformFee, expectedPlatformFee, "Platform fee tidak sesuai harapan");
        assertEq(actualOrganizerShare, expectedOrganizerShare, "Organizer fee tidak sesuai harapan");
        assertEq(buyerSpent, totalPurchaseAmount, "Pembeli membayar jumlah yang tidak sesuai");
        
        console.log("\n[OK] All fee distributions match expected amounts");
        console.log("=== Primary Purchase Fee Distribution Test PASSED! ===");
    }
    
    // Helper untuk membeli dan list tiket resale
    function _buyAndListTicket() internal returns (uint256) {
        // Beli tiket sebagai reseller
        vm.startPrank(reseller);
        idrx.approve(eventAddress, TICKET_PRICE);
        eventContract.purchaseTicket(0, 1);
        
        // Dapatkan tokenId
        uint256 tokenId = 0; // Biasanya token pertama adalah 0
        
        // List tiket untuk resale
        ticketNFT.approve(eventAddress, tokenId);
        eventContract.listTicketForResale(tokenId, RESALE_PRICE);
        vm.stopPrank();
        
        return tokenId;
    }
    
    // Test distribusi fee untuk pembelian tiket secondary (resale)
    function testResaleFeeDistribution() public {
        console.log("=== STEP 2: Resale Fee Distribution Test ===");
        
        // Setup tiket resale
        console.log("\n--- Setting Up Resale Ticket ---");
        uint256 tokenId = _buyAndListTicket();
        console.log("Resale ticket setup completed");
        console.log("Token ID listed for resale:", tokenId);
        console.log("Resale price:", RESALE_PRICE);
        console.log("Original price:", TICKET_PRICE);
        console.log("Markup percentage (basis points):", ((RESALE_PRICE - TICKET_PRICE) * 10000) / TICKET_PRICE);
        
        // Catat saldo awal sebelum pembelian resale
        uint256 initialOrganizerBalance = idrx.balanceOf(organizer);
        uint256 initialPlatformBalance = idrx.balanceOf(platformFeeReceiver);
        uint256 initialResellerBalance = idrx.balanceOf(reseller);
        uint256 initialBuyerBalance = idrx.balanceOf(buyer);
        
        // Log saldo awal untuk debugging
        console.log("\n--- Initial Balances Before Resale ---");
        console.log("Organizer address:", organizer);
        console.log("Platform receiver address:", platformFeeReceiver);
        console.log("Reseller address:", reseller);
        console.log("Buyer address:", buyer);
        console.log("  Organizer balance:", initialOrganizerBalance);
        console.log("  Platform balance:", initialPlatformBalance);
        console.log("  Reseller balance:", initialResellerBalance);
        console.log("  Buyer balance:", initialBuyerBalance);
        
        // Log fee structure
        console.log("\n--- Resale Fee Structure ---");
        console.log("Platform fee percentage (basis points):", PLATFORM_FEE_PERCENTAGE);
        console.log("Organizer fee percentage (basis points):", ORGANIZER_FEE_PERCENTAGE);
        console.log("Total fee percentage (basis points):", PLATFORM_FEE_PERCENTAGE + ORGANIZER_FEE_PERCENTAGE);
        
        // Beli tiket resale sebagai buyer
        console.log("\n--- Executing Resale Purchase ---");
        vm.startPrank(buyer);
        idrx.approve(eventAddress, RESALE_PRICE);
        console.log("Buyer approved amount:", RESALE_PRICE);
        eventContract.purchaseResaleTicket(tokenId);
        console.log("Resale purchase transaction completed");
        vm.stopPrank();
        
        // Hitung fee yang diharapkan untuk resale
        uint256 platformFee = (RESALE_PRICE * PLATFORM_FEE_PERCENTAGE) / Constants.BASIS_POINTS;
        uint256 organizerFee = (RESALE_PRICE * ORGANIZER_FEE_PERCENTAGE) / Constants.BASIS_POINTS;
        uint256 sellerAmount = RESALE_PRICE - platformFee - organizerFee;
        
        // Log pembayaran yang diharapkan
        console.log("\n--- Expected Resale Fee Distribution ---");
        console.log("Total resale amount:", RESALE_PRICE);
        console.log("Expected platform fee:", platformFee);
        console.log("Expected organizer fee:", organizerFee);
        console.log("Expected seller amount:", sellerAmount);
        console.log("Platform fee calculation: (resale_price * platform_percentage) / basis_points");
        console.log("Organizer fee calculation: (resale_price * organizer_percentage) / basis_points");
        
        // Verifikasi distribusi fee
        uint256 actualPlatformFee = idrx.balanceOf(platformFeeReceiver) - initialPlatformBalance;
        uint256 actualOrganizerFee = idrx.balanceOf(organizer) - initialOrganizerBalance;
        uint256 actualSellerAmount = idrx.balanceOf(reseller) - initialResellerBalance;
        uint256 buyerSpent = initialBuyerBalance - idrx.balanceOf(buyer);
        
        // Log distribusi aktual
        console.log("\n--- Actual Resale Fee Distribution ---");
        console.log("Platform received:", actualPlatformFee);
        console.log("Organizer received:", actualOrganizerFee);
        console.log("Seller received:", actualSellerAmount);
        console.log("Buyer spent:", buyerSpent);
        
        // Log final balances
        console.log("\n--- Final Account Balances ---");
        console.log("  Organizer balance:", idrx.balanceOf(organizer));
        console.log("  Platform balance:", idrx.balanceOf(platformFeeReceiver));
        console.log("  Reseller balance:", idrx.balanceOf(reseller));
        console.log("  Buyer balance:", idrx.balanceOf(buyer));
        
        // Verify token ownership transfer
        console.log("\n--- Token Ownership Transfer ---");
        console.log("New token owner:", ticketNFT.ownerOf(tokenId));
        console.log("Expected owner (buyer):", buyer);
        
        // Assertions
        assertEq(actualPlatformFee, platformFee, "Platform fee tidak sesuai harapan");
        assertEq(actualOrganizerFee, organizerFee, "Organizer fee tidak sesuai harapan");
        assertEq(actualSellerAmount, sellerAmount, "Seller amount tidak sesuai harapan");
        assertEq(buyerSpent, RESALE_PRICE, "Pembeli membayar jumlah yang tidak sesuai");
        
        console.log("\n[OK] All resale fee distributions match expected amounts");
        console.log("=== Resale Fee Distribution Test PASSED! ===");
    }
    
    // Test perubahan platform fee receiver
    function testPlatformFeeReceiver() public {
        // Setup - Test current platform fee receiver
        console.log("Current platformFeeReceiver:", platformFeeReceiver);
        
        // Beli tiket untuk menghasilkan fee
        vm.startPrank(buyer);
        idrx.approve(eventAddress, TICKET_PRICE);
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        
        // Verifikasi platform fee diterima dengan benar
        uint256 initialAmount = idrx.balanceOf(platformFeeReceiver);
        assertTrue(initialAmount > 0, "Platform fee tidak diterima");
        
        // Create new factory with different fee receiver
        address newReceiver = makeAddr("newFeeReceiver");
        console.log("New platformFeeReceiver:", newReceiver);
        
        vm.startPrank(makeAddr("newFactoryOwner"));
        EventFactory newFactory = new EventFactory(address(idrx), address(0));
        newFactory.setPlatformFeeReceiver(newReceiver);
        vm.stopPrank();
        
        // Create new event with different fee receiver
        vm.startPrank(organizer);
        address newEventAddr = newFactory.createEvent(
            "New Event",
            "Another concert",
            eventDate + 1 days,
            "Different Venue",
            "ipfs://new-metadata",
            false
        );
        
        Event newEvent = Event(newEventAddr);
        newEvent.addTicketTier("Regular", TICKET_PRICE, 100, 4);
        vm.stopPrank();
        
        // Purchase ticket from new event
        vm.startPrank(buyer);
        idrx.approve(newEventAddr, TICKET_PRICE);
        newEvent.purchaseTicket(0, 1);
        vm.stopPrank();
        
        // Verify fee received by new receiver
        uint256 newAmount = idrx.balanceOf(newReceiver);
        uint256 expectedFee = (TICKET_PRICE * PLATFORM_FEE_PERCENTAGE) / Constants.BASIS_POINTS;
        
        assertTrue(newAmount > 0, "Fee tidak diterima oleh penerima baru");
        assertEq(newAmount, expectedFee, "Fee tidak sesuai dengan yang diharapkan");
        
        // Verify old receiver didn't receive fee from new event
        assertEq(idrx.balanceOf(platformFeeReceiver), initialAmount, "Penerima lama menerima fee dari event baru");
    }
    
    // Test platform fee percentage
    function testPlatformFeePercentage() public {
        // Verifikasi platform fee di factory
        uint256 factoryPlatformFee = factory.getPlatformFeePercentage();
        assertEq(factoryPlatformFee, PLATFORM_FEE_PERCENTAGE, "Platform fee tidak sesuai dengan konstanta");
        
        // Beli tiket dan verifikasi fee
        vm.startPrank(buyer);
        idrx.approve(eventAddress, TICKET_PRICE);
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        
        // Hitung expected fee
        uint256 expectedFee = (TICKET_PRICE * PLATFORM_FEE_PERCENTAGE) / Constants.BASIS_POINTS;
        
        // Verifikasi fee diterima dengan benar
        uint256 actualFee = idrx.balanceOf(platformFeeReceiver);
        assertEq(actualFee, expectedFee, "Platform fee tidak sesuai harapan");
    }
}