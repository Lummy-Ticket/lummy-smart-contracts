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
        console.log("Testing Token ID generation...");
        
        // Purchase ticket from tier 1
        vm.startPrank(attendee1);
        idrxToken.approve(eventAddress, tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        // Check token ID format: 1[eventId][tier][sequential] (tier is 1-indexed in token ID)
        uint256 expectedTokenId = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 1;
        
        // Verify token was minted with correct ID
        assertEq(ticketNFT.ownerOf(expectedTokenId), attendee1);
        
        // Purchase another ticket from same tier
        vm.startPrank(attendee2);
        idrxToken.approve(eventAddress, tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        // Check second token ID
        uint256 expectedTokenId2 = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 2;
        assertEq(ticketNFT.ownerOf(expectedTokenId2), attendee2);
        
        // Purchase from tier 2
        vm.startPrank(attendee1);
        idrxToken.approve(eventAddress, tier2Price);
        eventContract.purchaseTicket(tier2Id, 1);
        vm.stopPrank();
        
        // Check tier 2 token ID
        uint256 expectedTokenId3 = (1 * 1e9) + (eventId * 1e6) + ((tier2Id + 1) * 1e5) + 1;
        assertEq(ticketNFT.ownerOf(expectedTokenId3), attendee1);
        
        console.log("Token ID generation test passed!");
    }
    
    // Test 2: Staff Management
    function testStaffManagement() public {
        console.log("Testing staff management...");
        
        // Initially, staff should not be whitelisted
        assertFalse(eventContract.staffWhitelist(staff1));
        
        // Add staff (only organizer can do this)
        vm.startPrank(organizer);
        eventContract.addStaff(staff1);
        vm.stopPrank();
        
        // Verify staff was added
        assertTrue(eventContract.staffWhitelist(staff1));
        
        // Add another staff
        vm.startPrank(organizer);
        eventContract.addStaff(staff2);
        vm.stopPrank();
        
        assertTrue(eventContract.staffWhitelist(staff2));
        
        // Remove staff
        vm.startPrank(organizer);
        eventContract.removeStaff(staff1);
        vm.stopPrank();
        
        // Verify staff was removed
        assertFalse(eventContract.staffWhitelist(staff1));
        assertTrue(eventContract.staffWhitelist(staff2)); // staff2 should still be there
        
        // Test access control - non-organizer cannot add staff
        vm.startPrank(attendee1);
        vm.expectRevert();
        eventContract.addStaff(staff1);
        vm.stopPrank();
        
        console.log("Staff management test passed!");
    }
    
    // Test 3: Ticket Status Updates
    function testTicketStatusUpdates() public {
        console.log("Testing ticket status updates...");
        
        // Purchase ticket
        vm.startPrank(attendee1);
        idrxToken.approve(eventAddress, tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        uint256 tokenId = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 1;
        
        // Check initial status
        assertEq(ticketNFT.getTicketStatus(tokenId), "valid");
        
        // Add staff
        vm.startPrank(organizer);
        eventContract.addStaff(staff1);
        vm.stopPrank();
        
        // Staff updates ticket status
        vm.startPrank(staff1);
        eventContract.updateTicketStatus(tokenId);
        vm.stopPrank();
        
        // Check updated status
        assertEq(ticketNFT.getTicketStatus(tokenId), "used");
        
        // Try to update again - should fail
        vm.startPrank(staff1);
        vm.expectRevert("Ticket not valid");
        eventContract.updateTicketStatus(tokenId);
        vm.stopPrank();
        
        // Non-staff cannot update
        vm.startPrank(attendee2);
        vm.expectRevert("Only staff can call");
        eventContract.updateTicketStatus(tokenId);
        vm.stopPrank();
        
        console.log("Ticket status update test passed!");
    }
    
    // Test 4: Event Cancellation and Refunds
    function testEventCancellationAndRefunds() public {
        console.log("Testing event cancellation and refunds...");
        
        // Purchase ticket
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
        
        // Cancel event (only organizer can do this)
        vm.startPrank(organizer);
        eventContract.cancelEvent();
        // Approve refund amount for the contract to spend
        idrxToken.approve(eventAddress, tier1Price);
        vm.stopPrank();
        
        // Verify event is cancelled
        assertTrue(eventContract.cancelled());
        
        // Claim refund
        vm.startPrank(attendee1);
        ticketNFT.claimRefund(tokenId);
        vm.stopPrank();
        
        // Check refund was processed
        uint256 finalBalance = idrxToken.balanceOf(attendee1);
        assertEq(finalBalance, initialBalance + tier1Price);
        
        // Check NFT was burned
        vm.expectRevert();
        ticketNFT.ownerOf(tokenId);
        
        // Note: Cannot check status after NFT is burned since token no longer exists
        // The refund process is complete when NFT is burned
        
        console.log("Event cancellation and refund test passed!");
    }
    
    // Test 5: Ticket Verification
    function testTicketVerification() public {
        console.log("Testing ticket verification...");
        
        // Purchase ticket
        vm.startPrank(attendee1);
        idrxToken.approve(eventAddress, tier1Price);
        eventContract.purchaseTicket(tier1Id, 1);
        vm.stopPrank();
        
        uint256 tokenId = (1 * 1e9) + (eventId * 1e6) + ((tier1Id + 1) * 1e5) + 1;
        
        // Generate ticket hash
        bytes32 ticketHash = ticketNFT.generateTicketHash(tokenId);
        
        // Verify ticket
        bool isValid = ticketNFT.verifyTicket(tokenId, ticketHash);
        assertTrue(isValid);
        
        // Test with wrong hash
        bytes32 wrongHash = keccak256("wrong");
        bool isInvalid = ticketNFT.verifyTicket(tokenId, wrongHash);
        assertFalse(isInvalid);
        
        // Use ticket
        vm.startPrank(organizer);
        eventContract.addStaff(staff1);
        vm.stopPrank();
        
        vm.startPrank(staff1);
        eventContract.updateTicketStatus(tokenId);
        vm.stopPrank();
        
        // Try to verify used ticket - should fail
        vm.expectRevert("TicketAlreadyUsed()");
        ticketNFT.verifyTicket(tokenId, ticketHash);
        
        console.log("Ticket verification test passed!");
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
        
        // 4. Pre-event verification
        bytes32 ticketHash = ticketNFT.generateTicketHash(tokenId);
        assertTrue(ticketNFT.verifyTicket(tokenId, ticketHash));
        
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