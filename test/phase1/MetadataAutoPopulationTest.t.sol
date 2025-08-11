// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "src/shared/contracts/TicketNFT.sol";
import "src/shared/libraries/Structs.sol";

/**
 * @title MetadataAutoPopulationTest
 * @notice Simple test for Phase 1.1 - NFT Metadata Auto-Population functionality
 * @dev Tests that TicketNFT.setEnhancedMetadata works correctly
 */
contract MetadataAutoPopulationTest is Test {
    TicketNFT public ticketNFT;
    
    address public owner = address(0x1);
    address public eventContract = address(0x2);
    address public buyer = address(0x3);
    
    // Test data
    string constant EVENT_NAME = "Test Concert 2025";
    string constant EVENT_VENUE = "Test Venue Jakarta";
    uint256 constant EVENT_DATE = 1735689600; // Jan 1, 2025
    string constant TIER_NAME = "VIP Access";
    string constant ORGANIZER_NAME = "0x1234567890abcdef1234567890abcdef12345678";
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy TicketNFT
        ticketNFT = new TicketNFT(address(0)); // No trusted forwarder for testing
        
        // Initialize NFT contract
        ticketNFT.initialize(EVENT_NAME, "TIX", eventContract);
        
        vm.stopPrank();
    }
    
    function testSetEnhancedMetadata() public {
        console.log("=== TESTING PHASE 1.1: setEnhancedMetadata FUNCTIONALITY ===");
        
        uint256 tokenId = 1000100001; // Test token ID
        
        // Mint test NFT (as event contract)
        vm.prank(eventContract);
        uint256 mintedTokenId = ticketNFT.mintTicket(buyer, 0, 100 * 1e18);
        
        console.log("Minted token ID:", mintedTokenId);
        
        // Get initial metadata (should have empty fields)
        Structs.TicketMetadata memory metadataBefore = ticketNFT.getTicketMetadata(mintedTokenId);
        console.log("Before setEnhancedMetadata:");
        console.log("- Event Name:", metadataBefore.eventName);
        console.log("- Event Venue:", metadataBefore.eventVenue);
        console.log("- Tier Name:", metadataBefore.tierName);
        
        // Test Phase 1.1 fix: Call setEnhancedMetadata (as event contract)
        vm.prank(eventContract);
        ticketNFT.setEnhancedMetadata(
            mintedTokenId,
            EVENT_NAME,
            EVENT_VENUE, 
            EVENT_DATE,
            TIER_NAME,
            ORGANIZER_NAME
        );
        
        // Verify metadata is populated
        Structs.TicketMetadata memory metadataAfter = ticketNFT.getTicketMetadata(mintedTokenId);
        console.log("After setEnhancedMetadata:");
        console.log("- Event Name:", metadataAfter.eventName);
        console.log("- Event Venue:", metadataAfter.eventVenue);
        console.log("- Event Date:", metadataAfter.eventDate);
        console.log("- Tier Name:", metadataAfter.tierName);
        console.log("- Organizer Name:", metadataAfter.organizerName);
        
        // Phase 1.1 Success Criteria: Metadata populated correctly
        assertEq(metadataAfter.eventName, EVENT_NAME, "Event name should be populated");
        assertEq(metadataAfter.eventVenue, EVENT_VENUE, "Event venue should be populated");  
        assertEq(metadataAfter.eventDate, EVENT_DATE, "Event date should be populated");
        assertEq(metadataAfter.tierName, TIER_NAME, "Tier name should be populated");
        assertEq(metadataAfter.organizerName, ORGANIZER_NAME, "Organizer name should be populated");
        
        console.log("[SUCCESS] setEnhancedMetadata working correctly!");
        console.log("[SUCCESS] Phase 1.1 Fix: No more empty metadata fields");
        
        // Test tokenURI generation
        string memory tokenURI = ticketNFT.tokenURI(mintedTokenId);
        assertTrue(bytes(tokenURI).length > 0, "TokenURI should not be empty");
        console.log("[SUCCESS] TokenURI generated successfully");
    }
    
}