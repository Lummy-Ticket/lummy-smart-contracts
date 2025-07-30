// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "src/shared/contracts/TicketNFT.sol";
import "src/legacy/contracts/Event.sol";
import "src/shared/libraries/Constants.sol";
import "forge-std/console.sol";

contract TicketNFTTest is Test {
    // Kontrak untuk testing
    TicketNFT public ticketNFT;
    Event public eventContract;
    
    // Alamat untuk testing
    address public deployer;
    address public organizer;
    address public eventAddress;
    address public attendee1;
    address public attendee2;
    
    // Data event
    string public eventName = "Konser Musik";
    uint256 public eventDate;
    
    
    // Custom error signatures for matching in tests
    bytes4 private constant _TICKET_ALREADY_USED_ERROR_SELECTOR = bytes4(keccak256("TicketAlreadyUsed()"));
    bytes4 private constant _ONLY_EVENT_CONTRACT_CAN_CALL_ERROR_SELECTOR = bytes4(keccak256("OnlyEventContractCanCall()"));
    
    function setUp() public {
        console.log("Setting up TicketNFT test environment");
        
        // Setup alamat untuk testing
        deployer = makeAddr("deployer");
        organizer = makeAddr("organizer");
        
        attendee1 = makeAddr("attendee1");
        
        attendee2 = makeAddr("attendee2");
        
        // Set tanggal event (30 hari di masa depan)
        eventDate = block.timestamp + 30 days;
        
        // Deploy dan setup kontrak Event
        vm.startPrank(organizer);
        
        // Deploy Event contract
        eventContract = new Event(address(0));
        
        // Initialize Event
        eventContract.initialize(
            organizer,
            eventName,
            "Konser musik spektakuler",
            eventDate,
            "Jakarta International Stadium",
            "ipfs://event-metadata"
        );
        
        eventAddress = address(eventContract);
        
        // Deploy TicketNFT
        ticketNFT = new TicketNFT(address(0));
        
        // Initialize TicketNFT
        ticketNFT.initialize(eventName, "TIX", eventAddress);
        
        // Setup TicketNFT di Event
        eventContract.setTicketNFT(address(ticketNFT), address(0x1), deployer);
        
        vm.stopPrank();
        
        console.log("TicketNFT deployed at:", address(ticketNFT));
        console.log("Event deployed at:", eventAddress);
    }
    
    // Test inisialisasi TicketNFT
    function testTicketNFTInitialization() public view {
        // Verifikasi event contract
        assertEq(ticketNFT.eventContract(), eventAddress);
        
        // Verifikasi owner adalah Event contract
        assertEq(ticketNFT.owner(), eventAddress);
    }
    
    // Helper function untuk minting tiket
    function _mintTicket(address to, uint256 tierId, uint256 price) internal returns (uint256) {
        vm.startPrank(eventAddress);
        uint256 tokenId = ticketNFT.mintTicket(to, tierId, price);
        vm.stopPrank();
        return tokenId;
    }
    
    // Test minting tiket
    function testMintTicket() public {
        uint256 tierId = 1;
        uint256 price = 100 * 10**2;
        
        // Event contract mints ticket to attendee1
        vm.startPrank(eventAddress);
        uint256 tokenId = ticketNFT.mintTicket(attendee1, tierId, price);
        vm.stopPrank();
        
        // Verifikasi tiket minted dengan benar
        assertEq(ticketNFT.ownerOf(tokenId), attendee1);
        assertEq(ticketNFT.balanceOf(attendee1), 1);
        
        // Verifikasi metadata tiket
        Structs.TicketMetadata memory metadata = ticketNFT.getTicketMetadata(tokenId);
            
        assertEq(metadata.eventId, 0);  // Event ID default adalah 0
        assertEq(metadata.tierId, tierId);
        assertEq(metadata.originalPrice, price);
        assertEq(metadata.used, false);
        assertEq(metadata.purchaseDate, block.timestamp);
    }
    
    // Test transfer tiket
    function testTransferTicket() public {
        // Mint tiket terlebih dahulu
        uint256 tokenId = _mintTicket(attendee1, 1, 100 * 10**2);
        
        // Attendee1 mentransfer tiket ke attendee2
        vm.startPrank(attendee1);
        ticketNFT.transferTicket(attendee2, tokenId);
        vm.stopPrank();
        
        // Verifikasi tiket ditransfer dengan benar
        assertEq(ticketNFT.ownerOf(tokenId), attendee2);
        assertEq(ticketNFT.balanceOf(attendee1), 0);
        assertEq(ticketNFT.balanceOf(attendee2), 1);
        
        // Verifikasi transfer count
        assertEq(ticketNFT.transferCount(tokenId), 1);
    }
    
    // Test ticket ownership verification
    function testVerifyTicketOwnership() public {
        // Mint tiket terlebih dahulu
        uint256 tokenId = _mintTicket(attendee1, 1, 100 * 10**2);
        
        // Verify ticket ownership by owner
        vm.startPrank(attendee1);
        bool isOwner = ticketNFT.verifyTicketOwnership(tokenId);
        assertTrue(isOwner);
        vm.stopPrank();
        
        // Verify ticket ownership by non-owner
        vm.startPrank(attendee2);
        bool isNotOwner = ticketNFT.verifyTicketOwnership(tokenId);
        assertFalse(isNotOwner);
        vm.stopPrank();
    }
    
    // Test use ticket by owner
    function testUseTicketByOwner() public {
        // Mint tiket terlebih dahulu
        uint256 tokenId = _mintTicket(attendee1, 1, 100 * 10**2);
        
        // Owner uses their own ticket
        vm.startPrank(attendee1);
        ticketNFT.useTicketByOwner(tokenId);
        vm.stopPrank();
        
        // Verify ticket is used
        Structs.TicketMetadata memory metadata = ticketNFT.getTicketMetadata(tokenId);
        assertTrue(metadata.used);
        
        // Test non-owner trying to use ticket
        uint256 tokenId2 = _mintTicket(attendee2, 1, 100 * 10**2);
        vm.startPrank(attendee1);
        vm.expectRevert("Not ticket owner");
        ticketNFT.useTicketByOwner(tokenId2);
        vm.stopPrank();
    }
    
    // Test penggunaan tiket
    function testUseTicket() public {
        // Mint tiket terlebih dahulu
        uint256 tokenId = _mintTicket(attendee1, 1, 100 * 10**2);
        
        // Gunakan tiket (hanya event contract yang bisa melakukan ini)
        vm.startPrank(eventAddress);
        ticketNFT.useTicket(tokenId);
        vm.stopPrank();
        
        // Verifikasi tiket telah digunakan
        Structs.TicketMetadata memory metadata = ticketNFT.getTicketMetadata(tokenId);
        assertTrue(metadata.used);
    }
    
    // Test verify ownership of used ticket fails
    function testRevertIfVerifyUsedTicketOwnership() public {
        // Mint tiket terlebih dahulu
        uint256 tokenId = _mintTicket(attendee1, 1, 100 * 10**2);
        
        // Gunakan tiket
        vm.startPrank(eventAddress);
        ticketNFT.useTicket(tokenId);
        vm.stopPrank();
        
        // Ekspektasi revert karena tiket sudah digunakan
        vm.startPrank(attendee1);
        vm.expectRevert(_TICKET_ALREADY_USED_ERROR_SELECTOR);
        ticketNFT.verifyTicketOwnership(tokenId);
        vm.stopPrank();
    }
    
    // Test penggunaan tiket hanya oleh event contract
    function testRevertIfUseTicketByNonEventContract() public {
        // Mint tiket terlebih dahulu
        uint256 tokenId = _mintTicket(attendee1, 1, 100 * 10**2);
        
        // Coba gunakan tiket sebagai attendee1 (bukan event contract)
        vm.startPrank(attendee1);
        
        // Ekspektasi revert
        vm.expectRevert(_ONLY_EVENT_CONTRACT_CAN_CALL_ERROR_SELECTOR);
        ticketNFT.useTicket(tokenId);
        vm.stopPrank();
    }
    
    // Test tiket tidak bisa ditransfer setelah digunakan
    function testRevertIfTransferUsedTicket() public {
        // Mint tiket terlebih dahulu
        uint256 tokenId = _mintTicket(attendee1, 1, 100 * 10**2);
        
        // Gunakan tiket
        vm.startPrank(eventAddress);
        ticketNFT.useTicket(tokenId);
        vm.stopPrank();
        
        // Coba transfer tiket yang sudah digunakan
        vm.startPrank(attendee1);
        
        // Ekspektasi revert
        vm.expectRevert(_TICKET_ALREADY_USED_ERROR_SELECTOR);
        ticketNFT.transferTicket(attendee2, tokenId);
        vm.stopPrank();
    }
    
    // Test mark transferred
    function testMarkTransferred() public {
        // Mint tiket terlebih dahulu
        uint256 tokenId = _mintTicket(attendee1, 1, 100 * 10**2);
        
        // Verifikasi transfer count awal
        assertEq(ticketNFT.transferCount(tokenId), 0);
        
        // Mark transferred (hanya event contract yang bisa melakukan ini)
        vm.startPrank(eventAddress);
        ticketNFT.markTransferred(tokenId);
        vm.stopPrank();
        
        // Verifikasi transfer count bertambah
        assertEq(ticketNFT.transferCount(tokenId), 1);
    }
}