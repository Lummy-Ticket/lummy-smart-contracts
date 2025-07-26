// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "src/core/EventFactory.sol";
import "src/core/Event.sol";
import "src/core/TicketNFT.sol";
import "src/core/MockIDRX.sol";
import "src/core/SimpleForwarder.sol";
import "src/libraries/Structs.sol";
import "src/libraries/Constants.sol";
import "forge-std/console.sol";

contract EnhancedFeaturesTest is Test {
    EventFactory public factory;
    MockIDRX public idrxToken;
    SimpleForwarder public forwarder;
    Event public eventContract;
    TicketNFT public ticketNFT;
    
    address public deployer = address(this);
    address public paymaster = makeAddr("paymaster");
    address public organizer = makeAddr("organizer");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    uint256 public eventDate;
    uint256 public tier1Price = 100 * 1e18;
    
    function setUp() public {
        console.log("Setting up Enhanced Features test environment");
        
        eventDate = block.timestamp + 30 days;
        
        // Deploy contracts
        idrxToken = new MockIDRX();
        forwarder = new SimpleForwarder(paymaster);
        factory = new EventFactory(address(idrxToken), address(forwarder));
        
        // Set factory as gas manager in forwarder
        vm.prank(paymaster);
        forwarder.setGasManager(address(factory));
        
        // Fund accounts
        idrxToken.mint(user1, 1000 * 1e18);
        idrxToken.mint(user2, 1000 * 1e18);
        idrxToken.mint(organizer, 1000 * 1e18);
        vm.deal(paymaster, 10 ether);
        
        // Create event
        vm.startPrank(organizer);
        address eventAddress = factory.createEvent(
            "Enhanced Test Event",
            "Testing enhanced features",
            eventDate,
            "Test Venue",
            "ipfs://metadata",
            true // Use Algorithm 1
        );
        vm.stopPrank();
        
        eventContract = Event(eventAddress);
        address nftAddress = eventContract.getTicketNFT();
        ticketNFT = TicketNFT(nftAddress);
        
        // Add ticket tier
        vm.startPrank(organizer);
        eventContract.addTicketTier("Regular", tier1Price, 100, 5);
        vm.stopPrank();
        
        console.log("Setup completed");
    }
    
    function testResaleRestrictionForUsedTickets() public {
        console.log("=== Testing Resale Restriction for Used/Scanned Tickets ===");
        
        // User1 purchases a ticket
        vm.startPrank(user1);
        idrxToken.approve(address(eventContract), tier1Price);
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        
        uint256 tokenId = generateTokenId(0, 0, 1); // eventId=0, tier=0, sequential=1
        
        console.log("Token ID:", tokenId);
        console.log("Token owner:", ticketNFT.ownerOf(tokenId));
        console.log("Initial ticket status:", ticketNFT.getTicketStatus(tokenId));
        
        // Initially, user should be able to list for resale
        vm.startPrank(user1);
        // Approve NFT transfer to event contract for resale
        ticketNFT.approve(address(eventContract), tokenId);
        eventContract.listTicketForResale(tokenId, tier1Price * 110 / 100);
        vm.stopPrank();
        
        console.log("[OK] Successfully listed valid ticket for resale");
        
        // Cancel the listing to test again
        vm.startPrank(user1);
        eventContract.cancelResaleListing(tokenId);
        vm.stopPrank();
        
        // Now mark ticket as used (simulate scanning)
        vm.startPrank(organizer);
        eventContract.updateTicketStatus(tokenId);
        vm.stopPrank();
        
        string memory newStatus = ticketNFT.getTicketStatus(tokenId);
        console.log("Ticket status after scanning:", newStatus);
        
        // Now user should NOT be able to list for resale
        vm.startPrank(user1);
        vm.expectRevert(TicketUsed.selector);
        eventContract.listTicketForResale(tokenId, tier1Price * 110 / 100);
        vm.stopPrank();
        
        console.log("[OK] Successfully prevented resale of used/scanned ticket");
        console.log("[SUCCESS] Resale restriction for used tickets working correctly!");
    }
    
    function testGasFeeManagement() public {
        console.log("=== Testing Gas Fee Management System ===");
        
        // Test setting max gas limit
        uint256 newMaxGas = 300000;
        factory.setMaxGasLimit(newMaxGas);
        assertEq(factory.maxGasLimit(), newMaxGas, "Max gas limit should be updated");
        console.log("[OK] Successfully set max gas limit to", newMaxGas);
        
        // Test setting gas buffer
        uint256 newGasBuffer = 30000;
        factory.setGasBuffer(newGasBuffer);
        assertEq(factory.gasBuffer(), newGasBuffer, "Gas buffer should be updated");
        console.log("[OK] Successfully set gas buffer to", newGasBuffer);
        
        // Test setting function-specific gas limit
        bytes4 purchaseSelector = Event.purchaseTicket.selector;
        uint256 purchaseGasLimit = 250000;
        factory.setFunctionGasLimit(purchaseSelector, purchaseGasLimit);
        
        uint256 retrievedLimit = factory.getFunctionGasLimit(purchaseSelector);
        assertEq(retrievedLimit, purchaseGasLimit, "Function gas limit should be set");
        console.log("[OK] Successfully set function-specific gas limit");
        
        // Test gas validation
        bool validGas = factory.validateGasLimit(200000, purchaseSelector);
        assertTrue(validGas, "200k gas should be valid for purchase function");
        
        bool invalidGas = factory.validateGasLimit(400000, purchaseSelector);
        assertFalse(invalidGas, "400k gas should be invalid for purchase function");
        console.log("[OK] Gas validation working correctly");
        
        console.log("[SUCCESS] Gas fee management system working correctly!");
    }
    
    function testForwarderGasValidation() public {
        console.log("=== Testing Forwarder Gas Validation ===");
        
        // Test default gas validation
        bytes memory dummyData = abi.encodeWithSelector(Event.purchaseTicket.selector, 0, 1);
        
        bool validGas = forwarder.validateGas(200000, dummyData);
        assertTrue(validGas, "200k gas should be valid by default");
        
        bool invalidGas = forwarder.validateGas(600000, dummyData);
        assertFalse(invalidGas, "600k gas should be invalid (exceeds default max)");
        console.log("[OK] Default gas validation working");
        
        // Test with gas manager integration
        // Set a lower limit for purchase function
        bytes4 purchaseSelector = Event.purchaseTicket.selector;
        factory.setFunctionGasLimit(purchaseSelector, 180000);
        
        validGas = forwarder.validateGas(150000, dummyData);
        assertTrue(validGas, "150k gas should be valid for purchase");
        
        invalidGas = forwarder.validateGas(200000, dummyData);
        assertFalse(invalidGas, "200k gas should be invalid for purchase (exceeds function limit)");
        console.log("[OK] Gas manager integration working");
        
        // Test disabling gas validation
        vm.prank(paymaster);
        forwarder.toggleGasValidation(false);
        
        bool anyGas = forwarder.validateGas(1000000, dummyData);
        assertTrue(anyGas, "Any gas should be valid when validation is disabled");
        console.log("[OK] Gas validation can be disabled");
        
        // Re-enable for other tests
        vm.prank(paymaster);
        forwarder.toggleGasValidation(true);
        
        console.log("[SUCCESS] Forwarder gas validation working correctly!");
    }
    
    function testGasLimitBoundaries() public {
        console.log("=== Testing Gas Limit Boundaries ===");
        
        // Test maximum gas limit enforcement
        vm.expectRevert("Gas limit too high");
        factory.setMaxGasLimit(1500000); // Above 1M limit
        
        // Test minimum gas limit enforcement  
        vm.expectRevert("Gas limit too low");
        factory.setMaxGasLimit(40000); // Below gas buffer
        
        console.log("[OK] Gas limit boundaries enforced");
        
        // Test forwarder boundaries
        vm.startPrank(paymaster);
        
        vm.expectRevert("Gas too high");
        forwarder.setDefaultMaxGas(1500000); // Above 1M limit
        
        vm.expectRevert("Gas too low");
        forwarder.setDefaultMaxGas(20000); // Below minimum
        
        vm.stopPrank();
        
        console.log("[OK] Forwarder gas boundaries enforced");
        console.log("[SUCCESS] Gas limit boundaries working correctly!");
    }
    
    function testResaleAfterRefund() public {
        console.log("=== Testing Resale Prevention After Refund ===");
        
        // User1 purchases a ticket
        vm.startPrank(user1);
        idrxToken.approve(address(eventContract), tier1Price);
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        
        uint256 tokenId = generateTokenId(0, 0, 1);
        
        // Cancel event (triggers automatic refund)
        vm.startPrank(organizer);
        eventContract.cancelEvent();
        vm.stopPrank();
        
        string memory statusAfterCancel = ticketNFT.getTicketStatus(tokenId);
        console.log("Ticket status after event cancellation:", statusAfterCancel);
        
        // Try to list refunded ticket for resale (should fail)
        vm.startPrank(user1);
        vm.expectRevert(EventIsCancelled.selector); // Event is cancelled, so this error will be thrown first
        eventContract.listTicketForResale(tokenId, tier1Price);
        vm.stopPrank();
        
        console.log("[OK] Successfully prevented resale of refunded ticket");
        console.log("[SUCCESS] Resale prevention after refund working correctly!");
    }
    
    function generateTokenId(uint256 eventId, uint256 tierCode, uint256 sequential) internal pure returns (uint256) {
        require(eventId <= 999, "Event ID too large");
        require(tierCode <= 9, "Tier code too large");
        require(sequential <= 99999, "Sequential number too large");
        
        uint256 actualTierCode = tierCode + 1;
        return (1 * 1e9) + (eventId * 1e6) + (actualTierCode * 1e5) + sequential;
    }
}