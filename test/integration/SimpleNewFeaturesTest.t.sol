// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {EventCoreFacet} from "src/diamond/facets/EventCoreFacet.sol";
import "src/shared/libraries/Structs.sol";

/**
 * @title SimpleNewFeaturesTest
 * @dev Test fitur baru tanpa kompleksitas Diamond setup
 */
contract SimpleNewFeaturesTest is Test {
    EventCoreFacet eventCore;
    address factory = address(this);
    address organizer = address(0x2);
    address user = address(0x3);

    function setUp() public {
        console.log("=== SETTING UP SIMPLE NEW FEATURES TEST ===");
        
        // Deploy EventCoreFacet
        eventCore = new EventCoreFacet(address(0));
        
        console.log("EventCoreFacet deployed at:", address(eventCore));
    }

    /**
     * Test initialize dengan category field baru
     */
    function testInitializeWithCategory() public {
        console.log("=== TESTING INITIALIZE WITH CATEGORY ===");
        
        // Mock factory setup
        vm.etch(address(eventCore), abi.encodePacked(
            type(EventCoreFacet).creationCode,
            abi.encode(address(0))
        ));
        
        // Test initialize dengan parameter baru
        eventCore.initialize(
            organizer,
            "Test Event",
            "Testing new category field",
            block.timestamp + 1 days,
            "Test Venue", 
            "ipfs://QmTest123",
            "Technology" // NEW: Category parameter
        );
        
        // Verify new getEventInfo return value
        (
            string memory name,
            string memory description,
            uint256 date,
            string memory venue,
            string memory category, // NEW FIELD
            address org
        ) = eventCore.getEventInfo();
        
        assertEq(name, "Test Event", "Event name should match");
        assertEq(category, "Technology", "Category should match");
        assertEq(org, organizer, "Organizer should match");
        
        console.log("SUCCESS: Initialize with category working");
        console.log("Category:", category);
    }

    /**
     * Test addTicketTier dengan description & benefits
     */
    function testAddTicketTierWithNewFields() public {
        console.log("=== TESTING ADD TICKET TIER WITH NEW FIELDS ===");
        
        // Initialize event first
        eventCore.initialize(
            organizer,
            "Tier Test Event",
            "Testing new tier fields",
            block.timestamp + 1 days,
            "Test Venue",
            "ipfs://test",
            "Music"
        );
        
        vm.startPrank(organizer);
        
        // Add tier dengan new fields
        eventCore.addTicketTier(
            "VIP Premium",
            500 ether, // 500 IDRX
            50,
            2,
            "Exclusive VIP experience with premium amenities", // NEW: Description
            '["Backstage access", "Meet & greet", "Premium bar", "VIP parking", "Exclusive merchandise"]' // NEW: Benefits JSON
        );
        
        // Get tier and verify new fields
        Structs.TicketTier memory tier = eventCore.getTicketTier(0);
        
        assertEq(tier.name, "VIP Premium", "Tier name should match");
        assertEq(tier.price, 500 ether, "Tier price should match");
        assertEq(tier.available, 50, "Tier availability should match");
        assertEq(tier.description, "Exclusive VIP experience with premium amenities", "Description should match");
        assertEq(tier.benefits, '["Backstage access", "Meet & greet", "Premium bar", "VIP parking", "Exclusive merchandise"]', "Benefits should match");
        
        console.log("SUCCESS: Add ticket tier with new fields working");
        console.log("Tier description:", tier.description);
        console.log("Tier benefits:", tier.benefits);
        
        vm.stopPrank();
    }

    /**
     * Test clearAllTiers functionality
     */
    function testClearAllTiers() public {
        console.log("=== TESTING CLEAR ALL TIERS FUNCTIONALITY ===");
        
        // Initialize event
        eventCore.initialize(
            organizer,
            "Clear Tiers Test",
            "Testing tier clearing",
            block.timestamp + 1 days,
            "Test Venue",
            "ipfs://test",
            "Sports"
        );
        
        vm.startPrank(organizer);
        
        // Add multiple tiers
        eventCore.addTicketTier("General", 100 ether, 100, 5, "General admission", '["Basic entry"]');
        eventCore.addTicketTier("Premium", 200 ether, 50, 3, "Premium seating", '["Premium seats", "Complimentary drinks"]');
        eventCore.addTicketTier("VIP", 300 ether, 20, 2, "VIP experience", '["VIP lounge", "Meet & greet", "Premium food"]');
        
        uint256 tierCountBefore = eventCore.getTierCount();
        assertEq(tierCountBefore, 3, "Should have 3 tiers before clearing");
        
        // Clear all tiers
        eventCore.clearAllTiers();
        
        uint256 tierCountAfter = eventCore.getTierCount();
        assertEq(tierCountAfter, 0, "Should have 0 tiers after clearing");
        
        console.log("SUCCESS: Clear all tiers functionality working");
        console.log("Tier count before:", tierCountBefore);
        console.log("Tier count after:", tierCountAfter);
        
        vm.stopPrank();
    }

    /**
     * Test IPFS metadata getter
     */
    function testIPFSMetadataGetter() public {
        console.log("=== TESTING IPFS METADATA GETTER ===");
        
        string memory expectedHash = "QmTestHashABC123DEF456";
        
        // Initialize dengan IPFS hash
        eventCore.initialize(
            organizer,
            "IPFS Test Event",
            "Testing IPFS metadata getter",
            block.timestamp + 1 days,
            "Digital Venue",
            expectedHash,
            "Technology"
        );
        
        // Get IPFS metadata via new getter
        string memory retrievedHash = eventCore.getIPFSMetadata();
        
        assertEq(retrievedHash, expectedHash, "IPFS hash should match");
        
        console.log("SUCCESS: IPFS metadata getter working");
        console.log("Expected hash:", expectedHash);
        console.log("Retrieved hash:", retrievedHash);
    }

    /**
     * Test multiple events simulation dengan tier reset
     */
    function testMultipleEventsWithTierReset() public {
        console.log("=== TESTING MULTIPLE EVENTS WITH TIER RESET ===");
        
        vm.startPrank(organizer);
        
        // === EVENT 1 ===
        eventCore.initialize(
            organizer,
            "Event 1",
            "First event",
            block.timestamp + 1 days,
            "Venue 1",
            "ipfs://event1",
            "Music"
        );
        
        // Add tiers to Event 1
        eventCore.addTicketTier("GA", 50 ether, 100, 5, "General admission", "[]");
        eventCore.addTicketTier("VIP", 150 ether, 30, 2, "VIP access", "[]");
        
        uint256 event1TierCount = eventCore.getTierCount();
        assertEq(event1TierCount, 2, "Event 1 should have 2 tiers");
        
        // Verify tier IDs are 0, 1
        Structs.TicketTier memory tier0 = eventCore.getTicketTier(0);
        Structs.TicketTier memory tier1 = eventCore.getTicketTier(1);
        assertEq(tier0.name, "GA", "First tier should be GA");
        assertEq(tier1.name, "VIP", "Second tier should be VIP");
        
        // === RESET FOR EVENT 2 ===
        eventCore.clearAllTiers();
        
        // === EVENT 2 ===
        eventCore.initialize(
            organizer,
            "Event 2",
            "Second event",
            block.timestamp + 2 days,  
            "Venue 2",
            "ipfs://event2",
            "Sports"
        );
        
        // Add tiers to Event 2 (should start from tier 0 again)
        eventCore.addTicketTier("Standard", 75 ether, 200, 8, "Standard seating", "[]");
        eventCore.addTicketTier("Premium", 125 ether, 100, 4, "Premium seating", "[]");
        eventCore.addTicketTier("Platinum", 200 ether, 50, 2, "Platinum experience", "[]");
        
        uint256 event2TierCount = eventCore.getTierCount();
        assertEq(event2TierCount, 3, "Event 2 should have 3 tiers after reset");
        
        // Verify tier IDs reset to 0, 1, 2 (not 3, 4, 5)
        Structs.TicketTier memory newTier0 = eventCore.getTicketTier(0);
        Structs.TicketTier memory newTier1 = eventCore.getTicketTier(1);
        Structs.TicketTier memory newTier2 = eventCore.getTicketTier(2);
        
        assertEq(newTier0.name, "Standard", "First tier should be Standard");
        assertEq(newTier1.name, "Premium", "Second tier should be Premium");
        assertEq(newTier2.name, "Platinum", "Third tier should be Platinum");
        
        console.log("SUCCESS: Multiple events with tier reset working");
        console.log("Event 1 had tiers:", event1TierCount);
        console.log("Event 2 has tiers:", event2TierCount);
        
        vm.stopPrank();
    }
    
    /**
     * Test error cases dan access control
     */
    function testErrorCases() public {
        console.log("=== TESTING ERROR CASES ===");
        
        // Initialize event
        eventCore.initialize(
            organizer,
            "Error Test",
            "Testing error cases",
            block.timestamp + 1 days,
            "Test Venue",
            "ipfs://test",
            "Technology"
        );
        
        // Test: Non-organizer cannot clear tiers
        vm.prank(user);
        vm.expectRevert();
        eventCore.clearAllTiers();
        
        // Test: Non-organizer cannot add tiers  
        vm.prank(user);
        vm.expectRevert();
        eventCore.addTicketTier(
            "Unauthorized",
            100 ether,
            10,
            1,
            "Should fail",
            "[]"
        );
        
        console.log("SUCCESS: Error cases working correctly");
    }
}