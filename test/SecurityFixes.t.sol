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

contract SecurityFixesTest is Test {
    EventFactory public factory;
    MockIDRX public idrxToken;
    SimpleForwarder public forwarder;
    Event public eventContract;
    TicketNFT public ticketNFT;
    
    address public deployer = address(this);
    address public paymaster = makeAddr("paymaster");
    address public organizer = makeAddr("organizer");
    address public staff1 = makeAddr("staff1");
    address public staff2 = makeAddr("staff2");
    address public manager1 = makeAddr("manager1");
    address public user1 = makeAddr("user1");
    
    uint256 public eventDate;
    uint256 public tier1Price = 100 * 1e18;
    
    function setUp() public {
        console.log("Setting up Security Fixes test environment");
        
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
        idrxToken.mint(organizer, 1000 * 1e18);
        vm.deal(paymaster, 10 ether);
        
        // Create event
        vm.startPrank(organizer);
        address eventAddress = factory.createEvent(
            "Security Test Event",
            "Testing security fixes",
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
    
    function testRoleBasedStaffManagement() public {
        console.log("=== Testing Role-Based Staff Management ===");
        
        // Check initial organizer role
        Event.StaffRole organizerRole = eventContract.getStaffRole(organizer);
        assertEq(uint256(organizerRole), uint256(Event.StaffRole.MANAGER), "Organizer should have MANAGER role");
        
        // Organizer can add staff with different roles
        vm.startPrank(organizer);
        
        // Add scanner staff
        eventContract.addStaffWithRole(staff1, Event.StaffRole.SCANNER);
        assertEq(uint256(eventContract.getStaffRole(staff1)), uint256(Event.StaffRole.SCANNER), "Staff1 should have SCANNER role");
        
        // Add checkin staff
        eventContract.addStaffWithRole(staff2, Event.StaffRole.CHECKIN);
        assertEq(uint256(eventContract.getStaffRole(staff2)), uint256(Event.StaffRole.CHECKIN), "Staff2 should have CHECKIN role");
        
        // Add manager staff
        eventContract.addStaffWithRole(manager1, Event.StaffRole.MANAGER);
        assertEq(uint256(eventContract.getStaffRole(manager1)), uint256(Event.StaffRole.MANAGER), "Manager1 should have MANAGER role");
        
        vm.stopPrank();
        
        console.log("[OK] Successfully assigned different staff roles");
        
        // Test that only MANAGER role can manage staff
        vm.startPrank(staff1); // SCANNER role
        vm.expectRevert("Insufficient staff privileges");
        eventContract.addStaffWithRole(user1, Event.StaffRole.SCANNER);
        vm.stopPrank();
        
        console.log("[OK] SCANNER role correctly prevented from managing staff");
        
        // Test that MANAGER can manage staff
        vm.startPrank(manager1);
        eventContract.addStaffWithRole(user1, Event.StaffRole.SCANNER);
        assertEq(uint256(eventContract.getStaffRole(user1)), uint256(Event.StaffRole.SCANNER), "Manager should be able to add staff");
        vm.stopPrank();
        
        console.log("[OK] MANAGER role can add staff");
        
        // Test that only organizer can assign/remove MANAGER role
        vm.startPrank(manager1);
        vm.expectRevert(abi.encodeWithSignature("OnlyOrganizerCanAssignManager()"));
        eventContract.addStaffWithRole(user1, Event.StaffRole.MANAGER);
        vm.stopPrank();
        
        console.log("[OK] Only organizer can assign MANAGER role");
        
        console.log("[SUCCESS] Role-based staff management working correctly!");
    }
    
    function testTicketScanningPermissions() public {
        console.log("=== Testing Ticket Scanning Permissions ===");
        
        // Purchase a ticket
        vm.startPrank(user1);
        idrxToken.approve(address(eventContract), tier1Price);
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        
        uint256 tokenId = generateTokenId(0, 0, 1);
        
        // Add different staff roles
        vm.startPrank(organizer);
        eventContract.addStaffWithRole(staff1, Event.StaffRole.SCANNER);
        eventContract.addStaffWithRole(staff2, Event.StaffRole.CHECKIN);
        eventContract.addStaffWithRole(manager1, Event.StaffRole.MANAGER);
        vm.stopPrank();
        
        // Test that all staff roles can scan tickets (SCANNER is minimum required)
        vm.startPrank(staff1); // SCANNER role
        eventContract.updateTicketStatus(tokenId);
        vm.stopPrank();
        
        string memory status = ticketNFT.getTicketStatus(tokenId);
        assertEq(status, "used", "SCANNER should be able to update ticket status");
        
        console.log("[OK] SCANNER role can scan tickets");
        
        // Reset ticket for next test (need to do this through event contract)
        // Let's purchase another ticket instead
        vm.startPrank(user1);
        idrxToken.approve(address(eventContract), tier1Price);
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        
        uint256 tokenId2 = generateTokenId(0, 0, 2);
        
        // Test CHECKIN role can also scan
        vm.startPrank(staff2); // CHECKIN role
        eventContract.updateTicketStatus(tokenId2);
        vm.stopPrank();
        
        status = ticketNFT.getTicketStatus(tokenId2);
        assertEq(status, "used", "CHECKIN should be able to update ticket status");
        
        console.log("[OK] CHECKIN role can scan tickets");
        
        // Test that non-staff cannot scan
        // Purchase another ticket for testing
        vm.startPrank(user1);
        idrxToken.approve(address(eventContract), tier1Price);
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        
        uint256 tokenId3 = generateTokenId(0, 0, 3);
        
        vm.startPrank(user1);
        vm.expectRevert("Insufficient staff privileges");
        eventContract.updateTicketStatus(tokenId3);
        vm.stopPrank();
        
        console.log("[OK] Non-staff correctly prevented from scanning");
        
        console.log("[SUCCESS] Ticket scanning permissions working correctly!");
    }
    
    function testAlgorithmLocking() public {
        console.log("=== Testing Algorithm Locking Mechanism ===");
        
        // Initially algorithm should not be locked
        assertFalse(eventContract.algorithmLocked(), "Algorithm should not be locked initially");
        
        // Only organizer can lock algorithm
        vm.startPrank(user1);
        vm.expectRevert();
        eventContract.lockAlgorithm();
        vm.stopPrank();
        
        console.log("[OK] Only organizer can lock algorithm");
        
        // Organizer can lock algorithm
        vm.startPrank(organizer);
        eventContract.lockAlgorithm();
        vm.stopPrank();
        
        assertTrue(eventContract.algorithmLocked(), "Algorithm should be locked");
        console.log("[OK] Algorithm successfully locked");
        
        // After locking, algorithm cannot be changed
        vm.startPrank(address(factory)); // Factory would normally be able to change algorithm
        vm.expectRevert("Algorithm is locked");
        eventContract.setAlgorithm1(false, 0);
        vm.stopPrank();
        
        console.log("[OK] Algorithm changes prevented after locking");
        
        console.log("[SUCCESS] Algorithm locking mechanism working correctly!");
    }
    
    function testLegacyStaffCompatibility() public {
        console.log("=== Testing Legacy Staff Function Compatibility ===");
        
        // Test legacy addStaff function
        vm.startPrank(organizer);
        eventContract.addStaff(staff1);
        vm.stopPrank();
        
        // Should have SCANNER role by default
        Event.StaffRole role = eventContract.getStaffRole(staff1);
        assertEq(uint256(role), uint256(Event.StaffRole.SCANNER), "Legacy addStaff should assign SCANNER role");
        
        // Should also be in legacy whitelist
        assertTrue(eventContract.isStaff(staff1), "Should be in legacy staff whitelist");
        
        console.log("[OK] Legacy addStaff function working");
        
        // Test legacy removeStaff function
        vm.startPrank(organizer);
        eventContract.removeStaff(staff1);
        vm.stopPrank();
        
        role = eventContract.getStaffRole(staff1);
        assertEq(uint256(role), uint256(Event.StaffRole.NONE), "Legacy removeStaff should remove role");
        
        assertFalse(eventContract.isStaff(staff1), "Should be removed from legacy whitelist");
        
        console.log("[OK] Legacy removeStaff function working");
        
        console.log("[SUCCESS] Legacy staff compatibility maintained!");
    }
    
    function testStaffRoleHierarchy() public {
        console.log("=== Testing Staff Role Hierarchy ===");
        
        // Add staff with different roles
        vm.startPrank(organizer);
        eventContract.addStaffWithRole(staff1, Event.StaffRole.SCANNER);
        eventContract.addStaffWithRole(staff2, Event.StaffRole.CHECKIN);
        eventContract.addStaffWithRole(manager1, Event.StaffRole.MANAGER);
        vm.stopPrank();
        
        // Test role hierarchy checks
        assertTrue(eventContract.hasStaffRole(staff1, Event.StaffRole.SCANNER), "SCANNER should have SCANNER privileges");
        assertFalse(eventContract.hasStaffRole(staff1, Event.StaffRole.CHECKIN), "SCANNER should not have CHECKIN privileges");
        
        assertTrue(eventContract.hasStaffRole(staff2, Event.StaffRole.SCANNER), "CHECKIN should have SCANNER privileges");
        assertTrue(eventContract.hasStaffRole(staff2, Event.StaffRole.CHECKIN), "CHECKIN should have CHECKIN privileges");
        assertFalse(eventContract.hasStaffRole(staff2, Event.StaffRole.MANAGER), "CHECKIN should not have MANAGER privileges");
        
        assertTrue(eventContract.hasStaffRole(manager1, Event.StaffRole.SCANNER), "MANAGER should have SCANNER privileges");
        assertTrue(eventContract.hasStaffRole(manager1, Event.StaffRole.CHECKIN), "MANAGER should have CHECKIN privileges");
        assertTrue(eventContract.hasStaffRole(manager1, Event.StaffRole.MANAGER), "MANAGER should have MANAGER privileges");
        
        console.log("[OK] Role hierarchy working correctly");
        
        console.log("[SUCCESS] Staff role hierarchy validated!");
    }
    
    function generateTokenId(uint256 eventId, uint256 tierCode, uint256 sequential) internal pure returns (uint256) {
        require(eventId <= 999, "Event ID too large");
        require(tierCode <= 9, "Tier code too large");
        require(sequential <= 99999, "Sequential number too large");
        
        uint256 actualTierCode = tierCode + 1;
        return (1 * 1e9) + (eventId * 1e6) + (actualTierCode * 1e5) + sequential;
    }
}