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

contract EnhancedRefundTest is Test {
    EventFactory public factory;
    MockIDRX public idrxToken;
    Event public eventContract;
    TicketNFT public ticketNFT;
    
    address public deployer = address(this);
    address public organizer = makeAddr("organizer");
    address public attendee1 = makeAddr("attendee1");
    address public attendee2 = makeAddr("attendee2");
    
    uint256 public eventId = 0;
    uint256 public tier1Price = 100 * 1e18;
    uint256 public eventDate;
    
    function setUp() public {
        console.log("Setting up Enhanced Refund test environment");
        
        // Set event date to future
        eventDate = block.timestamp + 30 days;
        
        // Deploy contracts
        idrxToken = new MockIDRX();
        factory = new EventFactory(address(idrxToken), address(0));
        
        // Fund test accounts
        idrxToken.mint(attendee1, 1000 * 1e18);
        idrxToken.mint(attendee2, 1000 * 1e18);
        idrxToken.mint(organizer, 1000 * 1e18);
        
        // Create Algorithm 1 event
        vm.startPrank(organizer);
        address eventAddress = factory.createEvent(
            "Test Event",
            "Description", 
            eventDate,
            "Venue",
            "ipfs://metadata",
            true  // Use Algorithm 1
        );
        vm.stopPrank();
        
        eventContract = Event(eventAddress);
        address nftAddress = eventContract.getTicketNFT();
        ticketNFT = TicketNFT(nftAddress);
        
        // Add ticket tier
        vm.startPrank(organizer);
        eventContract.addTicketTier("Regular", tier1Price, 100, 5);
        vm.stopPrank();
        
        console.log("Event created at:", eventAddress);
        console.log("NFT contract:", nftAddress);
    }
    
    function testAutomaticRefundOnCancellation() public {
        console.log("=== Testing Automatic Refund System ===");
        
        // Purchase tickets from multiple attendees
        vm.startPrank(attendee1);
        idrxToken.approve(address(eventContract), tier1Price);
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        
        vm.startPrank(attendee2);
        idrxToken.approve(address(eventContract), tier1Price * 2);
        eventContract.purchaseTicket(0, 2);
        vm.stopPrank();
        
        // Record initial balances
        uint256 attendee1InitialBalance = idrxToken.balanceOf(attendee1);
        uint256 attendee2InitialBalance = idrxToken.balanceOf(attendee2);
        uint256 organizerInitialBalance = idrxToken.balanceOf(organizer);
        
        console.log("Before cancellation:");
        console.log("- Attendee1 balance:", attendee1InitialBalance);
        console.log("- Attendee2 balance:", attendee2InitialBalance);
        console.log("- Organizer balance:", organizerInitialBalance);
        console.log("- Event contract balance:", idrxToken.balanceOf(address(eventContract)));
        
        // Generate token IDs for verification
        uint256 token1 = generateTokenId(eventId, 0, 1);
        uint256 token2 = generateTokenId(eventId, 0, 2);
        uint256 token3 = generateTokenId(eventId, 0, 3);
        
        // Verify ticket statuses before cancellation
        assertEq(ticketNFT.getTicketStatus(token1), "valid");
        assertEq(ticketNFT.getTicketStatus(token2), "valid");
        assertEq(ticketNFT.getTicketStatus(token3), "valid");
        
        // Cancel event (should trigger automatic refunds)
        vm.startPrank(organizer);
        eventContract.cancelEvent();
        vm.stopPrank();
        
        // Check final balances - should show automatic refunds processed
        uint256 attendee1FinalBalance = idrxToken.balanceOf(attendee1);
        uint256 attendee2FinalBalance = idrxToken.balanceOf(attendee2);
        
        console.log("After cancellation:");
        console.log("- Attendee1 balance:", attendee1FinalBalance);
        console.log("- Attendee2 balance:", attendee2FinalBalance);
        console.log("- Event contract balance:", idrxToken.balanceOf(address(eventContract)));
        
        // Verify automatic refunds were processed
        assertEq(attendee1FinalBalance, attendee1InitialBalance + tier1Price, "Attendee1 should receive full refund");
        assertEq(attendee2FinalBalance, attendee2InitialBalance + (tier1Price * 2), "Attendee2 should receive full refund");
        
        // Verify ticket statuses were updated to "refunded"
        assertEq(ticketNFT.getTicketStatus(token1), "refunded");
        assertEq(ticketNFT.getTicketStatus(token2), "refunded");
        assertEq(ticketNFT.getTicketStatus(token3), "refunded");
        
        console.log("[SUCCESS] Automatic refund system working correctly!");
    }
    
    function testOrganizerEscrowSystem() public {
        console.log("=== Testing Organizer Escrow System ===");
        
        // Purchase ticket
        vm.startPrank(attendee1);
        idrxToken.approve(address(eventContract), tier1Price);
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        
        // Check that organizer doesn't get funds immediately (they're in escrow)
        uint256 organizerBalance = idrxToken.balanceOf(organizer);
        uint256 escrowAmount = eventContract.organizerEscrow(organizer);
        
        console.log("Organizer direct balance:", organizerBalance);
        console.log("Organizer escrow amount:", escrowAmount);
        
        assertEq(escrowAmount, tier1Price, "Funds should be in escrow");
        
        // Try to withdraw before event completion - should fail
        vm.startPrank(organizer);
        vm.expectRevert("Event not completed yet");
        eventContract.withdrawOrganizerFunds();
        vm.stopPrank();
        
        // Complete event (simulate event completion)
        vm.warp(eventDate + 2 days); // Move past event date + grace period
        vm.startPrank(organizer);
        eventContract.markEventCompleted();
        vm.stopPrank();
        
        // Now organizer should be able to withdraw
        uint256 balanceBefore = idrxToken.balanceOf(organizer);
        vm.startPrank(organizer);
        eventContract.withdrawOrganizerFunds();
        vm.stopPrank();
        
        uint256 balanceAfter = idrxToken.balanceOf(organizer);
        assertEq(balanceAfter - balanceBefore, tier1Price, "Organizer should receive escrowed funds");
        assertEq(eventContract.organizerEscrow(organizer), 0, "Escrow should be cleared");
        
        console.log("[SUCCESS] Escrow system working correctly!");
    }
    
    function testEmergencyRefundForUsers() public {
        console.log("=== Testing Emergency Refund Function ===");
        
        // Purchase ticket
        vm.startPrank(attendee1);
        idrxToken.approve(address(eventContract), tier1Price);
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        
        uint256 tokenId = generateTokenId(eventId, 0, 1);
        uint256 initialBalance = idrxToken.balanceOf(attendee1);
        
        // Try emergency refund before cancellation - should fail
        vm.startPrank(attendee1);
        vm.expectRevert("Event not cancelled");
        eventContract.emergencyRefund(tokenId);
        vm.stopPrank();
        
        // Cancel event
        vm.startPrank(organizer);
        eventContract.cancelEvent();
        vm.stopPrank();
        
        // Ticket should already be refunded automatically, so manual emergency refund should fail
        vm.startPrank(attendee1);
        vm.expectRevert("Ticket not eligible for refund");
        eventContract.emergencyRefund(tokenId);
        vm.stopPrank();
        
        // But verify the automatic refund worked
        uint256 finalBalance = idrxToken.balanceOf(attendee1);
        assertEq(finalBalance, initialBalance + tier1Price, "Automatic refund should have processed");
        
        console.log("[SUCCESS] Emergency refund system working correctly!");
    }
    
    function generateTokenId(uint256 _eventId, uint256 tierCode, uint256 sequential) internal pure returns (uint256) {
        require(_eventId <= 999, "Event ID too large");
        require(tierCode <= 9, "Tier code too large");
        require(sequential <= 99999, "Sequential number too large");
        
        uint256 actualTierCode = tierCode + 1;
        return (1 * 1e9) + (_eventId * 1e6) + (actualTierCode * 1e5) + sequential;
    }
}