// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {TicketNFT} from "src/shared/contracts/TicketNFT.sol";
import "src/shared/libraries/Structs.sol";
import "src/shared/libraries/Base64.sol";
import "src/shared/libraries/Strings.sol";

/**
 * @title NFTMetadataTest
 * @dev Test dynamic NFT metadata generation and tokenURI
 */
contract NFTMetadataTest is Test {
    using Strings for uint256;
    using Base64 for bytes;

    TicketNFT ticketNFT;
    address eventContract = address(this);
    address owner = address(0x1);
    address user = address(0x2);

    function setUp() public {
        console.log("=== SETTING UP NFT METADATA TEST ===");
        
        vm.startPrank(owner);
        
        // Deploy TicketNFT contract
        ticketNFT = new TicketNFT(address(0)); // No trusted forwarder for test
        
        // Initialize with event name
        ticketNFT.initialize("Test Event", "TEST", eventContract);
        
        vm.stopPrank();
        
        console.log("TicketNFT deployed at:", address(ticketNFT));
    }

    /**
     * Test basic NFT minting and metadata
     */
    function testBasicNFTMinting() public {
        console.log("=== TESTING BASIC NFT MINTING ===");
        
        // Mint a ticket NFT
        uint256 tokenId = ticketNFT.mintTicket(
            user,
            0, // tierId
            100 ether // originalPrice
        );
        
        console.log("Minted token ID:", tokenId);
        
        // Verify ownership
        address tokenOwner = ticketNFT.ownerOf(tokenId);
        assertEq(tokenOwner, user, "Token should be owned by user");
        
        // Get metadata
        Structs.TicketMetadata memory metadata = ticketNFT.getTicketMetadata(tokenId);
        assertEq(metadata.tierId, 0, "Tier ID should match");
        assertEq(metadata.originalPrice, 100 ether, "Price should match");
        assertEq(metadata.status, "valid", "Status should be valid");
        
        console.log("SUCCESS: Basic NFT minting working");
    }

    /**
     * Test enhanced metadata setting
     */
    function testEnhancedMetadata() public {
        console.log("=== TESTING ENHANCED METADATA ===");
        
        // Mint ticket
        uint256 tokenId = ticketNFT.mintTicket(user, 0, 250 ether);
        
        // Set enhanced metadata
        ticketNFT.setEnhancedMetadata(
            tokenId,
            "Summer Music Festival 2025",
            "GBK Stadium",
            1735689600, // Jan 1, 2025
            "VIP Gold",
            "Event Organizer Inc"
        );
        
        // Get metadata and verify
        Structs.TicketMetadata memory metadata = ticketNFT.getTicketMetadata(tokenId);
        assertEq(metadata.eventName, "Summer Music Festival 2025", "Event name should match");
        assertEq(metadata.eventVenue, "GBK Stadium", "Venue should match");
        assertEq(metadata.eventDate, 1735689600, "Date should match");
        assertEq(metadata.tierName, "VIP Gold", "Tier name should match");
        assertEq(metadata.organizerName, "Event Organizer Inc", "Organizer should match");
        
        console.log("Event name:", metadata.eventName);
        console.log("Venue:", metadata.eventVenue);
        console.log("Tier:", metadata.tierName);
        
        console.log("SUCCESS: Enhanced metadata working");
    }

    /**
     * Test dynamic tokenURI generation
     */
    function testDynamicTokenURI() public {
        console.log("=== TESTING DYNAMIC TOKEN URI ===");
        
        // Mint ticket
        uint256 tokenId = ticketNFT.mintTicket(user, 1, 500 ether);
        
        // Set enhanced metadata
        ticketNFT.setEnhancedMetadata(
            tokenId,
            "Tech Conference 2025",
            "Convention Center",
            1735689600,
            "Premium",
            "TechOrg"
        );
        
        // Get tokenURI (should be dynamic base64 JSON)
        string memory tokenURI = ticketNFT.tokenURI(tokenId);
        
        console.log("Token URI length:", bytes(tokenURI).length);
        console.log("Token URI prefix:", substring(tokenURI, 0, 50));
        
        // Verify it starts with data:application/json;base64,
        assertTrue(startsWith(tokenURI, "data:application/json;base64,"), "TokenURI should start with proper data URI");
        assertTrue(bytes(tokenURI).length > 100, "TokenURI should not be empty/short");
        
        console.log("SUCCESS: Dynamic tokenURI generation working");
    }

    /**
     * Test status updates and metadata changes
     */
    function testStatusUpdates() public {
        console.log("=== TESTING STATUS UPDATES ===");
        
        // Mint ticket
        uint256 tokenId = ticketNFT.mintTicket(user, 0, 100 ether);
        
        // Verify initial status
        string memory initialStatus = ticketNFT.getTicketStatus(tokenId);
        assertEq(initialStatus, "valid", "Initial status should be valid");
        
        // Update status to used (contract sudah di-initialize di setUp)
        ticketNFT.updateStatus(tokenId, "used");
        
        string memory updatedStatus = ticketNFT.getTicketStatus(tokenId);
        assertEq(updatedStatus, "used", "Status should be updated to used");
        
        // Verify metadata reflects the change
        Structs.TicketMetadata memory metadata = ticketNFT.getTicketMetadata(tokenId);
        assertEq(metadata.status, "used", "Metadata status should be updated");
        assertTrue(metadata.used, "Used flag should be true");
        
        console.log("Initial status:", initialStatus);
        console.log("Updated status:", updatedStatus);
        
        console.log("SUCCESS: Status updates working");
    }

    /**
     * Test multiple NFTs with different metadata
     */
    function testMultipleNFTsWithDifferentMetadata() public {
        console.log("=== TESTING MULTIPLE NFTs WITH DIFFERENT METADATA ===");
        
        address user1 = address(0x10);
        address user2 = address(0x20);
        address user3 = address(0x30);
        
        // Mint different tier tickets
        uint256 token1 = ticketNFT.mintTicket(user1, 0, 50 ether);   // General
        uint256 token2 = ticketNFT.mintTicket(user2, 1, 100 ether);  // Premium
        uint256 token3 = ticketNFT.mintTicket(user3, 2, 200 ether);  // VIP
        
        // Set different metadata for each
        ticketNFT.setEnhancedMetadata(token1, "Music Fest", "Park", 1735689600, "General", "MusicCorp");
        ticketNFT.setEnhancedMetadata(token2, "Music Fest", "Park", 1735689600, "Premium", "MusicCorp");
        ticketNFT.setEnhancedMetadata(token3, "Music Fest", "Park", 1735689600, "VIP", "MusicCorp");
        
        // Update one ticket to used (contract sudah di-initialize di setUp)
        ticketNFT.updateStatus(token2, "used");
        
        // Verify each has unique characteristics
        Structs.TicketMetadata memory meta1 = ticketNFT.getTicketMetadata(token1);
        Structs.TicketMetadata memory meta2 = ticketNFT.getTicketMetadata(token2);
        Structs.TicketMetadata memory meta3 = ticketNFT.getTicketMetadata(token3);
        
        assertEq(meta1.tierName, "General", "Token 1 should be General tier");
        assertEq(meta2.tierName, "Premium", "Token 2 should be Premium tier");
        assertEq(meta3.tierName, "VIP", "Token 3 should be VIP tier");
        
        assertEq(meta1.status, "valid", "Token 1 should be valid");
        assertEq(meta2.status, "used", "Token 2 should be used");
        assertEq(meta3.status, "valid", "Token 3 should be valid");
        
        assertEq(meta1.originalPrice, 50 ether, "Token 1 price should match");
        assertEq(meta2.originalPrice, 100 ether, "Token 2 price should match");
        assertEq(meta3.originalPrice, 200 ether, "Token 3 price should match");
        
        console.log("Token 1 - Tier:", meta1.tierName, "Status:", meta1.status);
        console.log("Token 2 - Tier:", meta2.tierName, "Status:", meta2.status);
        console.log("Token 3 - Tier:", meta3.tierName, "Status:", meta3.status);
        
        console.log("SUCCESS: Multiple NFTs with different metadata working");
    }

    /**
     * Test ticket transfer and metadata persistence
     */
    function testTicketTransferAndMetadata() public {
        console.log("=== TESTING TICKET TRANSFER AND METADATA ===");
        
        address originalOwner = address(0x100);
        address newOwner = address(0x200);
        
        // Mint ticket
        uint256 tokenId = ticketNFT.mintTicket(originalOwner, 0, 150 ether);
        
        // Set metadata
        ticketNFT.setEnhancedMetadata(
            tokenId,
            "Sports Event",
            "Stadium",
            1735689600,
            "Premium",
            "SportsCorp"
        );
        
        // Verify initial ownership and metadata
        assertEq(ticketNFT.ownerOf(tokenId), originalOwner, "Should be owned by original owner");
        
        Structs.TicketMetadata memory metaBefore = ticketNFT.getTicketMetadata(tokenId);
        assertEq(metaBefore.transferCount, 0, "Transfer count should be 0 initially");
        
        // Transfer ticket
        vm.prank(originalOwner);
        ticketNFT.transferTicket(newOwner, tokenId);
        
        // Verify new ownership
        assertEq(ticketNFT.ownerOf(tokenId), newOwner, "Should be owned by new owner");
        
        // Verify metadata persistence and transfer count update
        Structs.TicketMetadata memory metaAfter = ticketNFT.getTicketMetadata(tokenId);
        assertEq(metaAfter.eventName, "Sports Event", "Event name should persist");
        assertEq(metaAfter.tierName, "Premium", "Tier name should persist");
        assertEq(metaAfter.transferCount, 1, "Transfer count should increment");
        
        console.log("Transfer count before:", metaBefore.transferCount);
        console.log("Transfer count after:", metaAfter.transferCount);
        
        console.log("SUCCESS: Ticket transfer and metadata persistence working");
    }

    // Helper functions for string operations
    function startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        
        if (prefixBytes.length > strBytes.length) {
            return false;
        }
        
        for (uint i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) {
                return false;
            }
        }
        
        return true;
    }
    
    function substring(string memory str, uint startIndex, uint length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (startIndex >= strBytes.length) {
            return "";
        }
        
        uint endIndex = startIndex + length;
        if (endIndex > strBytes.length) {
            endIndex = strBytes.length;
        }
        
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        
        return string(result);
    }
}