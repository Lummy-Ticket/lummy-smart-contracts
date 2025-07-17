// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "src/core/EventFactory.sol";
import "src/core/Event.sol";
import "src/core/TicketNFT.sol";
import "src/core/MockIDRX.sol";
import "src/libraries/Structs.sol";
import "src/libraries/Constants.sol";
import "forge-std/console.sol";

contract Algorithm1Test is Test {
    // Contracts
    EventFactory public factory;
    Event public eventContract;
    TicketNFT public ticketNFT;
    MockIDRX public idrxToken;
    
    // Test addresses
    address public organizer;
    address public staff1;
    address public staff2;
    address public attendee1;
    address public attendee2;
    address public platformFeeReceiver;
    
    // Test data
    string public eventName = "Algorithm 1 Test Event";
    string public eventDescription = "Test event for Algorithm 1";
    uint256 public eventDate;
    string public eventVenue = "Test Venue";
    string public eventMetadata = "ipfs://test-metadata";
    
    // Event and tier data
    uint256 public eventId;
    address public eventAddress;
    uint256 public tier1Id = 0;
    uint256 public tier2Id = 1;
    uint256 public tier1Price = 100 * 10**18; // 100 IDRX
    uint256 public tier2Price = 200 * 10**18; // 200 IDRX
    
    function setUp() public {
        console.log("Setting up Algorithm 1 test environment");
        
        // Setup test addresses
        organizer = makeAddr("organizer");
        staff1 = makeAddr("staff1");
        staff2 = makeAddr("staff2");
        attendee1 = makeAddr("attendee1");
        attendee2 = makeAddr("attendee2");
        platformFeeReceiver = makeAddr("platformFeeReceiver");
        
        // Set event date (future)
        eventDate = block.timestamp + 30 days;
        
        // Deploy IDRX token
        idrxToken = new MockIDRX();
        
        // Deploy factory
        factory = new EventFactory(address(idrxToken), address(0));
        
        // Create event with Algorithm 1
        vm.startPrank(organizer);
        eventAddress = factory.createEvent(
            eventName,
            eventDescription,
            eventDate,
            eventVenue,
            eventMetadata,
            true // useAlgorithm1
        );
        vm.stopPrank();
        
        // Get event contract
        eventContract = Event(eventAddress);
        
        // Get event ID
        eventId = factory.eventCounter() - 1;
        
        // Get NFT contract
        address nftAddress = eventContract.getTicketNFT();
        ticketNFT = TicketNFT(nftAddress);
        
        // Setup ticket tiers
        vm.startPrank(organizer);
        eventContract.addTicketTier(
            "Regular",
            tier1Price,
            100,
            10
        );
        eventContract.addTicketTier(
            "VIP",
            tier2Price,
            50,
            5
        );
        vm.stopPrank();
        
        // Mint some IDRX for attendees
        idrxToken.mint(attendee1, 1000 * 10**18);
        idrxToken.mint(attendee2, 1000 * 10**18);
        
        console.log("Event created at:", eventAddress);
        console.log("Event ID:", eventId);
        console.log("NFT contract:", nftAddress);
    }
    
    // Test 1: Token ID Generation
    function testTokenIdGeneration() public {
        console.log("=== LANGKAH 1: Test Pembuatan Token ID ===");
        console.log("Event ID:", eventId);
        console.log("Tier 1 ID:", tier1Id);
        console.log("Tier 2 ID:", tier2Id);
        console.log("Harga Tier 1:", tier1Price);
        console.log("Harga Tier 2:", tier2Price);
        
        // Purchase ticket from tier 1
        console.log("\n--- Pembelian Tiket Tier 1 oleh Attendee1 ---");
        console.log("Alamat Attendee1:", attendee1);
        console.log("Saldo IDRX awal:", idrxToken.balanceOf(attendee1));
        
        vm.startPrank(attendee1);
        idrxToken.approve(eventAddress, tier1Price);
        console.log("IDRX yang disetujui:", tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        // Check token ID format: 1[eventId][tier][sequential] (tier is 1-indexed in token ID)
        uint256 expectedTokenId = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 1;
        console.log("Token ID yang diharapkan:", expectedTokenId);
        console.log("Breakdown Token ID:");
        console.log("  Algoritma: 1");
        console.log("  Event ID:", eventId);
        console.log("  Kode Tier (1-indexed):", tier1Id + 1);
        console.log("  Urutan: 1");
        
        // Verify token was minted with correct ID
        address tokenOwner = ticketNFT.ownerOf(expectedTokenId);
        console.log("Pemilik token:", tokenOwner);
        console.log("Pemilik yang diharapkan:", attendee1);
        assertEq(tokenOwner, attendee1);
        console.log("[OK] Token ID 1 berhasil dibuat dengan benar");
        
        // Purchase another ticket from same tier
        console.log("\n--- Purchase Tier 1 Ticket by Attendee2 ---");
        console.log("Attendee2 address:", attendee2);
        vm.startPrank(attendee2);
        idrxToken.approve(eventAddress, tier1Price);
        console.log("Approved IDRX:", tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        // Check second token ID
        uint256 expectedTokenId2 = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 2;
        console.log("Expected Token ID 2:", expectedTokenId2);
        console.log("Token ID breakdown:");
        console.log("  Algorithm: 1");
        console.log("  Event ID:", eventId);
        console.log("  Tier Code (1-indexed):", tier1Id + 1);
        console.log("  Sequential: 2");
        
        address tokenOwner2 = ticketNFT.ownerOf(expectedTokenId2);
        console.log("Token owner:", tokenOwner2);
        console.log("Expected owner:", attendee2);
        assertEq(tokenOwner2, attendee2);
        console.log("[OK] Token ID 2 generated correctly");
        
        // Purchase from tier 2
        console.log("\n--- Purchase Tier 2 Ticket by Attendee1 ---");
        vm.startPrank(attendee1);
        idrxToken.approve(eventAddress, tier2Price);
        console.log("Approved IDRX:", tier2Price);
        eventContract.purchaseTicket(tier2Id, 1);
        vm.stopPrank();
        
        // Check tier 2 token ID
        uint256 expectedTokenId3 = (1 * 1e9) + (eventId * 1e6) + ((tier2Id + 1) * 1e5) + 1;
        console.log("Expected Token ID 3:", expectedTokenId3);
        console.log("Token ID breakdown:");
        console.log("  Algorithm: 1");
        console.log("  Event ID:", eventId);
        console.log("  Tier Code (1-indexed):", tier2Id + 1);
        console.log("  Sequential: 1");
        
        address tokenOwner3 = ticketNFT.ownerOf(expectedTokenId3);
        console.log("Token owner:", tokenOwner3);
        console.log("Expected owner:", attendee1);
        assertEq(tokenOwner3, attendee1);
        console.log("[OK] Token ID 3 generated correctly");
        
        console.log("\n=== Test Pembuatan Token ID BERHASIL! ===");
    }
    
    // Test 2: Staff Management
    function testStaffManagement() public {
        console.log("=== STEP 2: Staff Management Test ===");
        console.log("Organizer address:", organizer);
        console.log("Staff1 address:", staff1);
        console.log("Staff2 address:", staff2);
        console.log("Attendee1 address:", attendee1);
        
        // Initially, staff should not be whitelisted
        console.log("\n--- Initial Staff Status Check ---");
        bool isStaff1Initial = eventContract.staffWhitelist(staff1);
        bool isStaff2Initial = eventContract.staffWhitelist(staff2);
        console.log("Staff1 initial status:", isStaff1Initial);
        console.log("Staff2 initial status:", isStaff2Initial);
        assertFalse(isStaff1Initial);
        assertFalse(isStaff2Initial);
        console.log("[OK] Initially no staff whitelisted");
        
        // Add staff (only organizer can do this)
        console.log("\n--- Adding Staff1 by Organizer ---");
        vm.startPrank(organizer);
        eventContract.addStaff(staff1);
        vm.stopPrank();
        console.log("Staff1 added successfully");
        
        // Verify staff was added
        bool isStaff1Added = eventContract.staffWhitelist(staff1);
        console.log("Staff1 status after adding:", isStaff1Added);
        assertTrue(isStaff1Added);
        console.log("[OK] Staff1 successfully added to whitelist");
        
        // Add another staff
        console.log("\n--- Adding Staff2 by Organizer ---");
        vm.startPrank(organizer);
        eventContract.addStaff(staff2);
        vm.stopPrank();
        console.log("Staff2 added successfully");
        
        bool isStaff2Added = eventContract.staffWhitelist(staff2);
        console.log("Staff2 status after adding:", isStaff2Added);
        assertTrue(isStaff2Added);
        console.log("[OK] Staff2 successfully added to whitelist");
        
        // Remove staff
        console.log("\n--- Removing Staff1 by Organizer ---");
        vm.startPrank(organizer);
        eventContract.removeStaff(staff1);
        vm.stopPrank();
        console.log("Staff1 removed successfully");
        
        // Verify staff was removed
        bool isStaff1Removed = eventContract.staffWhitelist(staff1);
        bool isStaff2StillThere = eventContract.staffWhitelist(staff2);
        console.log("Staff1 status after removal:", isStaff1Removed);
        console.log("Staff2 status after Staff1 removal:", isStaff2StillThere);
        assertFalse(isStaff1Removed);
        assertTrue(isStaff2StillThere); // staff2 should still be there
        console.log("[OK] Staff1 successfully removed, Staff2 still whitelisted");
        
        // Test access control - non-organizer cannot add staff
        console.log("\n--- Testing Access Control ---");
        console.log("Attempting to add staff by non-organizer (should fail)");
        vm.startPrank(attendee1);
        vm.expectRevert();
        eventContract.addStaff(staff1);
        vm.stopPrank();
        console.log("[OK] Non-organizer correctly rejected from adding staff");
        
        // Final status check
        console.log("\n--- Final Staff Status ---");
        console.log("Staff1 final status:", eventContract.staffWhitelist(staff1));
        console.log("Staff2 final status:", eventContract.staffWhitelist(staff2));
        
        console.log("\n=== Staff Management Test PASSED! ===");
    }
    
    // Test 3: Ticket Status Updates
    function testTicketStatusUpdates() public {
        console.log("=== STEP 3: Ticket Status Updates Test ===");
        
        // Purchase ticket
        console.log("\n--- Purchase Ticket for Status Testing ---");
        console.log("Attendee1 purchasing ticket...");
        vm.startPrank(attendee1);
        idrxToken.approve(eventAddress, tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        uint256 tokenId = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 1;
        console.log("Token ID:", tokenId);
        console.log("Token owner:", ticketNFT.ownerOf(tokenId));
        
        // Check initial status
        console.log("\n--- Initial Ticket Status Check ---");
        string memory initialStatus = ticketNFT.getTicketStatus(tokenId);
        console.log("Initial ticket status:", initialStatus);
        assertEq(initialStatus, "valid");
        console.log("[OK] Ticket initially has 'valid' status");
        
        // Add staff
        console.log("\n--- Adding Staff for Status Updates ---");
        vm.startPrank(organizer);
        eventContract.addStaff(staff1);
        vm.stopPrank();
        console.log("Staff1 added to whitelist");
        console.log("Staff1 whitelist status:", eventContract.staffWhitelist(staff1));
        
        // Staff updates ticket status
        console.log("\n--- Staff Updates Ticket Status ---");
        console.log("Staff1 updating ticket status from 'valid' to 'used'");
        vm.startPrank(staff1);
        eventContract.updateTicketStatus(tokenId);
        vm.stopPrank();
        
        // Check updated status
        string memory updatedStatus = ticketNFT.getTicketStatus(tokenId);
        console.log("Updated ticket status:", updatedStatus);
        assertEq(updatedStatus, "used");
        console.log("[OK] Ticket status successfully updated to 'used'");
        
        // Try to update again - should fail
        console.log("\n--- Testing Double Update Prevention ---");
        console.log("Attempting to update 'used' ticket (should fail)");
        vm.startPrank(staff1);
        vm.expectRevert("Ticket not valid");
        eventContract.updateTicketStatus(tokenId);
        vm.stopPrank();
        console.log("[OK] Double update correctly prevented");
        
        // Non-staff cannot update
        console.log("\n--- Testing Access Control ---");
        console.log("Attempting update by non-staff (should fail)");
        vm.startPrank(attendee2);
        vm.expectRevert("Only staff can call");
        eventContract.updateTicketStatus(tokenId);
        vm.stopPrank();
        console.log("[OK] Non-staff correctly rejected from updating status");
        
        // Final status verification
        console.log("\n--- Final Status Verification ---");
        string memory finalStatus = ticketNFT.getTicketStatus(tokenId);
        console.log("Final ticket status:", finalStatus);
        console.log("Token still owned by:", ticketNFT.ownerOf(tokenId));
        
        console.log("\n=== Ticket Status Updates Test PASSED! ===");
    }
    
    // Test 4: Event Cancellation and Refunds
    function testEventCancellationAndRefunds() public {
        console.log("=== STEP 4: Event Cancellation and Refunds Test ===");
        
        // Purchase ticket
        console.log("\n--- Purchase Ticket for Refund Testing ---");
        console.log("Attendee1 initial balance:", idrxToken.balanceOf(attendee1));
        console.log("Organizer initial balance:", idrxToken.balanceOf(organizer));
        
        vm.startPrank(attendee1);
        idrxToken.approve(eventAddress, tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        uint256 tokenId = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 1;
        uint256 initialBalance = idrxToken.balanceOf(attendee1);
        
        console.log("Generated token ID:", tokenId);
        console.log("Event ID:", eventId);
        console.log("Tier ID:", tier1Id);
        console.log("Token exists:", ticketNFT.balanceOf(attendee1) > 0);
        console.log("Attendee1 balance after purchase:", initialBalance);
        console.log("Organizer balance after purchase:", idrxToken.balanceOf(organizer));
        console.log("Ticket owner:", ticketNFT.ownerOf(tokenId));
        
        // Check initial event status
        console.log("\n--- Initial Event Status ---");
        console.log("Event cancelled status:", eventContract.cancelled());
        console.log("Ticket status:", ticketNFT.getTicketStatus(tokenId));
        
        // Cancel event (only organizer can do this)
        console.log("\n--- Cancel Event by Organizer ---");
        vm.startPrank(organizer);
        eventContract.cancelEvent();
        console.log("Event cancelled");
        // Approve refund amount for the contract to spend
        idrxToken.approve(eventAddress, tier1Price);
        console.log("Organizer approved refund amount:", tier1Price);
        vm.stopPrank();
        
        // Verify event is cancelled
        bool isCancelled = eventContract.cancelled();
        console.log("Event cancelled status after cancellation:", isCancelled);
        assertTrue(isCancelled);
        console.log("[OK] Event successfully cancelled");
        
        // Check balances before refund
        console.log("\n--- Balances Before Refund ---");
        console.log("Attendee1 balance:", idrxToken.balanceOf(attendee1));
        console.log("Organizer balance:", idrxToken.balanceOf(organizer));
        console.log("Ticket status before refund:", ticketNFT.getTicketStatus(tokenId));
        
        // Claim refund
        console.log("\n--- Claim Refund Process ---");
        console.log("Attendee1 claiming refund for token:", tokenId);
        vm.startPrank(attendee1);
        ticketNFT.claimRefund(tokenId);
        vm.stopPrank();
        console.log("Refund claimed successfully");
        
        // Check refund was processed
        console.log("\n--- Refund Verification ---");
        uint256 finalBalance = idrxToken.balanceOf(attendee1);
        uint256 organizerFinalBalance = idrxToken.balanceOf(organizer);
        console.log("Attendee1 final balance:", finalBalance);
        console.log("Organizer final balance:", organizerFinalBalance);
        console.log("Expected final balance:", initialBalance + tier1Price);
        console.log("Actual refund amount:", finalBalance - initialBalance);
        
        assertEq(finalBalance, initialBalance + tier1Price);
        console.log("[OK] Refund amount correct");
        
        // Check NFT was burned
        console.log("\n--- NFT Burn Verification ---");
        console.log("Checking if NFT was burned...");
        vm.expectRevert();
        ticketNFT.ownerOf(tokenId);
        console.log("[OK] NFT successfully burned after refund");
        
        console.log("Attendee1 NFT balance after refund:", ticketNFT.balanceOf(attendee1));
        
        // Note: Cannot check status after NFT is burned since token no longer exists
        // The refund process is complete when NFT is burned
        
        console.log("\n=== Event Cancellation and Refund Test PASSED! ===");
    }
    
    // Test 5: Skenario Verifikasi Tiket (6 Langkah)
    function testTicketVerification() public {
        console.log("=== SKENARIO VERIFIKASI TIKET (6 LANGKAH) ===");
        
        // Setup: Purchase ticket
        console.log("\n--- Setup: Pembelian Tiket ---");
        vm.startPrank(attendee1);
        idrxToken.approve(eventAddress, tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        uint256 tokenId = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 1;
        console.log("Tiket berhasil dibeli dengan Token ID:", tokenId);
        console.log("Pemilik tiket:", ticketNFT.ownerOf(tokenId));
        console.log("Status awal tiket:", ticketNFT.getTicketStatus(tokenId));
        
        // LANGKAH 1: User scan berisi token id
        console.log("\n=== LANGKAH 1: USER SCAN QR CODE BERISI TOKEN ID ===");
        console.log("User memindai QR code di venue");
        console.log("QR code berisi Token ID:", tokenId);
        console.log("Sistem menerima Token ID dari scan QR");
        
        // LANGKAH 2: Smart contract verify NFT ownership dan status valid
        console.log("\n=== LANGKAH 2: SMART CONTRACT VERIFY NFT OWNERSHIP DAN STATUS ===");
        console.log("Sistem melakukan verifikasi kepemilikan NFT...");
        
        // Check if token exists
        address tokenOwner = ticketNFT.ownerOf(tokenId);
        console.log("Token ditemukan, pemilik:", tokenOwner);
        
        // Check token status
        string memory currentStatus = ticketNFT.getTicketStatus(tokenId);
        console.log("Status tiket saat ini:", currentStatus);
        
        // Verify ownership (simulation - this would be called by the venue system)
        vm.startPrank(attendee1);
        bool isOwnerValid = ticketNFT.verifyTicketOwnership(tokenId);
        vm.stopPrank();
        
        console.log("Hasil verifikasi kepemilikan:", isOwnerValid ? "VALID" : "INVALID");
        console.log("Hasil verifikasi status:", keccak256(bytes(currentStatus)) == keccak256(bytes("valid")) ? "VALID" : "INVALID");
        assertTrue(isOwnerValid, "Kepemilikan tiket harus valid");
        assertEq(currentStatus, "valid", "Status tiket harus valid");
        console.log("[OK] Verifikasi kepemilikan dan status berhasil");
        
        // LANGKAH 3: Sistem inisiasi metadata update
        console.log("\n=== LANGKAH 3: SISTEM INISIASI METADATA UPDATE ===");
        console.log("Sistem venue menginisiasi proses update metadata...");
        console.log("Menyiapkan transaksi untuk mengubah status tiket");
        console.log("Target perubahan: 'valid' -> 'used'");
        
        // LANGKAH 4: User menerima approval request untuk approve NFT
        console.log("\n=== LANGKAH 4: USER MENERIMA APPROVAL REQUEST ===");
        console.log("User menerima notifikasi approval request di wallet");
        console.log("Request: Approve transaksi untuk mengubah status NFT");
        console.log("User address:", attendee1);
        console.log("Action: useTicketByOwner(", tokenId, ")");
        console.log("User mengklik 'Approve' di wallet...");
        
        // LANGKAH 5: User approve dan metadata status berubah menjadi "used"
        console.log("\n=== LANGKAH 5: USER APPROVE DAN METADATA STATUS BERUBAH ===");
        console.log("User memberikan approval untuk transaksi");
        console.log("Menjalankan transaksi useTicketByOwner...");
        
        // User approves the transaction
        vm.startPrank(attendee1);
        ticketNFT.useTicketByOwner(tokenId);
        vm.stopPrank();
        
        string memory newStatus = ticketNFT.getTicketStatus(tokenId);
        console.log("Status tiket setelah approve:", newStatus);
        assertEq(newStatus, "used", "Status harus berubah menjadi 'used'");
        console.log("[OK] Metadata berhasil diupdate menjadi 'used'");
        
        // LANGKAH 6: User bisa masuk ke venue
        console.log("\n=== LANGKAH 6: USER BISA MASUK KE VENUE ===");
        console.log("Sistem venue memverifikasi status tiket telah berubah");
        console.log("Status tiket sekarang:", newStatus);
        console.log("Akses venue: DIIZINKAN");
        console.log("User berhasil masuk ke venue!");
        
        // Test case: Mencoba menggunakan tiket yang sudah digunakan
        console.log("\n--- Test: Mencoba Scan Tiket yang Sudah Digunakan ---");
        console.log("Simulasi: User lain mencoba scan tiket yang sama");
        vm.startPrank(attendee1);
        vm.expectRevert("TicketAlreadyUsed()");
        ticketNFT.verifyTicketOwnership(tokenId);
        vm.stopPrank();
        console.log("[OK] Tiket yang sudah digunakan ditolak dengan benar");
        
        // Test case: Non-owner mencoba menggunakan tiket orang lain
        console.log("\n--- Test: Non-Owner Mencoba Menggunakan Tiket Orang Lain ---");
        // Beli tiket untuk attendee2
        vm.startPrank(attendee2);
        idrxToken.approve(eventAddress, tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        uint256 tokenId2 = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 2;
        console.log("Tiket baru untuk test, Token ID:", tokenId2);
        console.log("Pemilik tiket:", ticketNFT.ownerOf(tokenId2));
        
        console.log("Simulasi: attendee1 mencoba menggunakan tiket attendee2");
        vm.startPrank(attendee1);
        vm.expectRevert("Not ticket owner");
        ticketNFT.useTicketByOwner(tokenId2);
        vm.stopPrank();
        console.log("[OK] Non-owner ditolak dengan benar");
        
        console.log("\n=== SKENARIO VERIFIKASI TIKET BERHASIL! ===");
    }
    
    // Test 6: Complete Event Flow
    function testCompleteEventFlow() public {
        console.log("Testing complete event flow...");
        
        // 1. Event creation (already done in setUp)
        assertTrue(eventContract.useAlgorithm1());
        
        // 2. Staff setup
        vm.startPrank(organizer);
        eventContract.addStaff(staff1);
        eventContract.addStaff(staff2);
        vm.stopPrank();
        
        // 3. Ticket purchase
        vm.startPrank(attendee1);
        idrxToken.approve(eventAddress, tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        uint256 tokenId = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 1;
        
        // 4. Pre-event verification (ownership-based)
        vm.startPrank(attendee1);
        bool isOwner = ticketNFT.verifyTicketOwnership(tokenId);
        assertTrue(isOwner);
        vm.stopPrank();
        
        // 5. Event entry (staff scans and updates status)
        vm.startPrank(staff1);
        eventContract.updateTicketStatus(tokenId);
        vm.stopPrank();
        
        // 6. Verify ticket is used
        assertEq(ticketNFT.getTicketStatus(tokenId), "used");
        
        console.log("Complete event flow test passed!");
    }
    
    // Test 7: Error Handling
    function testErrorHandling() public {
        console.log("Testing error handling...");
        
        // Test refund without cancellation
        vm.startPrank(attendee1);
        idrxToken.approve(eventAddress, tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        uint256 tokenId = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 1;
        
        // Try to claim refund without cancellation
        vm.startPrank(attendee1);
        vm.expectRevert("Event not cancelled");
        ticketNFT.claimRefund(tokenId);
        vm.stopPrank();
        
        // Test staff access control
        vm.startPrank(attendee1);
        vm.expectRevert("Only staff can call");
        eventContract.updateTicketStatus(tokenId);
        vm.stopPrank();
        
        // Test organizer access control
        vm.startPrank(attendee1);
        vm.expectRevert();
        eventContract.addStaff(staff1);
        vm.stopPrank();
        
        console.log("Error handling test passed!");
    }
    
    // Test 8: Token ID Parsing
    function testTokenIdParsing() public {
        console.log("Testing token ID parsing...");
        
        // Generate token ID
        uint256 expectedEventId = eventId;
        uint256 expectedTier = tier1Id + 1; // Tier is 1-indexed in token ID
        uint256 expectedSequential = 1;
        
        uint256 generatedTokenId = (1 * 1e9) + (expectedEventId * 1e6) + (expectedTier * 1e5) + expectedSequential;
        
        // Parse token ID
        uint256 algorithm = generatedTokenId / 1e9;
        uint256 parsedEventId = (generatedTokenId % 1e9) / 1e6;
        uint256 parsedTier = (generatedTokenId % 1e6) / 1e5;
        uint256 parsedSequential = generatedTokenId % 1e5;
        
        // Verify parsing
        assertEq(algorithm, 1);
        assertEq(parsedEventId, expectedEventId);
        assertEq(parsedTier, expectedTier);
        assertEq(parsedSequential, expectedSequential);
        
        console.log("Token ID parsing test passed!");
    }
}