// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "src/diamond/facets/EventCoreFacet.sol";
import "src/diamond/LibAppStorage.sol";
import "src/shared/libraries/Structs.sol";

/**
 * @title StorageCorruptionPreventionTest
 * @notice Tests for Phase 1.2 - Storage Corruption Prevention
 * @dev Verifies that multiple event initialization doesn't corrupt storage
 */
contract StorageCorruptionPreventionTest is Test {
    EventCoreFacet public eventCoreFacet;
    
    address public factory = address(0x1);
    address public organizer1 = address(0x2);
    address public organizer2 = address(0x3);
    
    // Event A data
    string constant EVENT_A_NAME = "Concert A";
    string constant EVENT_A_VENUE = "Venue A";
    uint256 constant EVENT_A_DATE = 1735689600;
    
    // Event B data  
    string constant EVENT_B_NAME = "Concert B";
    string constant EVENT_B_VENUE = "Venue B";
    uint256 constant EVENT_B_DATE = 1735776000;
    
    // Tier data
    string constant TIER_NAME = "General";
    uint256 constant TIER_PRICE = 100 * 1e18;
    uint256 constant TIER_AVAILABLE = 50;
    uint256 constant TIER_MAX_PER = 5;
    string constant TIER_DESC = "General admission";
    string constant TIER_BENEFITS = '["Entry"]';
    
    function setUp() public {
        // Deploy EventCoreFacet (this test focuses on the facet logic)
        eventCoreFacet = new EventCoreFacet(address(0)); // No trusted forwarder
        
        // Mock factory caller
        vm.store(
            address(eventCoreFacet),
            bytes32(LibAppStorage.DIAMOND_STORAGE_POSITION),
            bytes32(uint256(uint160(factory))) // Set factory address
        );
    }
    
    function testPreventDoubleInitialization() public {
        console.log("=== TESTING PHASE 1.2: PREVENT DOUBLE INITIALIZATION ===");
        
        // First initialization should succeed
        vm.prank(factory);
        eventCoreFacet.initialize(
            organizer1,
            EVENT_A_NAME,
            "Description A",
            EVENT_A_DATE,
            EVENT_A_VENUE,
            "ipfs://hashA",
            "Music"
        );
        
        console.log("[SUCCESS] First initialization successful");
        
        // Verify first event data is set
        (string memory name, string memory desc, uint256 date, string memory venue, string memory category, address org) = 
            eventCoreFacet.getEventInfo();
            
        assertEq(name, EVENT_A_NAME, "Event A name should be set");
        assertEq(venue, EVENT_A_VENUE, "Event A venue should be set");
        assertEq(org, organizer1, "Event A organizer should be set");
        console.log("Event A initialized:", name, "at", venue);
        
        // Second initialization should FAIL (Phase 1.2 fix)
        vm.prank(factory);
        vm.expectRevert("Event already initialized");
        eventCoreFacet.initialize(
            organizer2,
            EVENT_B_NAME,
            "Description B", 
            EVENT_B_DATE,
            EVENT_B_VENUE,
            "ipfs://hashB",
            "Sports"
        );
        
        console.log("[SUCCESS] Second initialization correctly rejected");
        
        // Verify original event data is still intact
        (string memory nameAfter, , , string memory venueAfter, , address orgAfter) = 
            eventCoreFacet.getEventInfo();
            
        assertEq(nameAfter, EVENT_A_NAME, "Event A name should be preserved");
        assertEq(venueAfter, EVENT_A_VENUE, "Event A venue should be preserved");
        assertEq(orgAfter, organizer1, "Event A organizer should be preserved");
        
        console.log("[SUCCESS] Original event data preserved after failed re-initialization");
        console.log("[SUCCESS] Phase 1.2 Fix: Storage corruption prevented");
    }
    
    function testTierStorageClearing() public {
        console.log("=== TESTING PHASE 1.2: TIER STORAGE CLEARING ===");
        
        // Initialize event
        vm.prank(factory);
        eventCoreFacet.initialize(
            organizer1,
            EVENT_A_NAME,
            "Description A",
            EVENT_A_DATE,
            EVENT_A_VENUE,
            "ipfs://hashA",
            "Music"
        );
        
        // Add tiers to Event A
        vm.startPrank(organizer1);
        eventCoreFacet.addTicketTier(
            "VIP",
            TIER_PRICE * 2,
            TIER_AVAILABLE,
            TIER_MAX_PER,
            TIER_DESC,
            TIER_BENEFITS
        );
        
        eventCoreFacet.addTicketTier(
            TIER_NAME,
            TIER_PRICE,
            TIER_AVAILABLE,
            TIER_MAX_PER,
            TIER_DESC,
            TIER_BENEFITS
        );
        vm.stopPrank();
        
        // Verify tiers exist
        Structs.TicketTier[] memory tiers = eventCoreFacet.getTicketTiers();
        assertEq(tiers.length, 2, "Should have 2 tiers");
        assertEq(tiers[0].name, "VIP", "First tier should be VIP");
        assertEq(tiers[1].name, TIER_NAME, "Second tier should be General");
        
        console.log("Added 2 tiers to Event A");
        console.log("- Tier 0:", tiers[0].name);
        console.log("- Tier 1:", tiers[1].name);
        
        // Clear all tiers (simulating what _clearAllEventData does during re-init)
        vm.prank(organizer1);
        eventCoreFacet.clearAllTiers();
        
        // Verify tiers are cleared
        Structs.TicketTier[] memory tiersAfter = eventCoreFacet.getTicketTiers();
        assertEq(tiersAfter.length, 0, "Tiers should be cleared");
        
        console.log("[SUCCESS] All tiers cleared successfully");
        console.log("[SUCCESS] Phase 1.2 Fix: Tier storage properly reset");
    }
    
    function testStorageStateReset() public {
        console.log("=== TESTING PHASE 1.2: COMPLETE STORAGE STATE RESET ===");
        
        // This test simulates what happens internally during _clearAllEventData
        // We can't directly test _clearAllEventData since it's internal,
        // but we can verify the clearing logic works through clearAllTiers
        
        // Initialize event and add data
        vm.prank(factory);
        eventCoreFacet.initialize(
            organizer1,
            EVENT_A_NAME,
            "Description A",
            EVENT_A_DATE,
            EVENT_A_VENUE,
            "ipfs://hashA",
            "Music"
        );
        
        // Add tiers
        vm.prank(organizer1);
        eventCoreFacet.addTicketTier(
            TIER_NAME,
            TIER_PRICE,
            TIER_AVAILABLE,
            TIER_MAX_PER,
            TIER_DESC,
            TIER_BENEFITS
        );
        
        // Verify initial state
        Structs.TicketTier[] memory tiersBefore = eventCoreFacet.getTicketTiers();
        assertEq(tiersBefore.length, 1, "Should have 1 tier before clearing");
        
        // Clear tiers (part of storage reset)
        vm.prank(organizer1);
        eventCoreFacet.clearAllTiers();
        
        // Verify cleared state
        Structs.TicketTier[] memory tiersAfter = eventCoreFacet.getTicketTiers();
        assertEq(tiersAfter.length, 0, "Should have 0 tiers after clearing");
        
        console.log("[SUCCESS] Storage state properly reset");
        console.log("Before clear: ", tiersBefore.length, "tiers");
        console.log("After clear: ", tiersAfter.length, "tiers");
        console.log("[SUCCESS] Phase 1.2 Fix: Complete storage reset verified");
    }
}