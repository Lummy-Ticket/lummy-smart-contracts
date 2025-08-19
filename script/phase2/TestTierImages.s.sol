// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {EventCoreFacet} from "src/diamond/facets/EventCoreFacet.sol";
import {TicketNFT} from "src/shared/contracts/TicketNFT.sol";

/**
 * @title Test Tier Images Script
 * @notice Script to test tier image functionality on deployed contracts
 */
contract TestTierImages is Script {
    
    // Deployed contract addresses (Lisk Sepolia)
    address constant DIAMOND_LUMMY = 0x0ba2A9C5C3BBa9cf2A19E8e6FB81A0f71B4b2d16;
    address constant TICKET_NFT = 0x09bbe505783947Aec530a94c1Cf3CB2B9c43BBBE;
    
    // User's current token (Backstage Pass)
    uint256 constant USER_TOKEN_ID = 1000300001;
    
    // Tier image hashes from user's IPFS metadata
    string[] tierImageHashes;

    function setUp() public {
        // Setup tier image hashes from user's actual IPFS data
        tierImageHashes.push("bafkreidxew3tj6gpqtoqecx5yurfhxupvaxzbisvuhhde726pgdemo55ki"); // Tier 0 - General Admission
        tierImageHashes.push("bafkreiewghbw4hoakd73i6427pn6yqihxadygstrdz4a2gdr2u533ghsme"); // Tier 1 - VIP Experience  
        tierImageHashes.push("bafkreihrsx5edwyikqsspxxvownc7wzwc6g7nzdholitoiconccluamaua"); // Tier 2 - Backstage Pass
    }

    function run() external {
        console.log("=== Testing Tier Images on Deployed Contracts ===");
        console.log("Diamond Address:", DIAMOND_LUMMY);
        console.log("TicketNFT Address:", TICKET_NFT);
        console.log("User Token ID:", USER_TOKEN_ID);
        
        // Test tier extraction from user's current token
        testTierExtraction();
        
        // Test current NFT metadata 
        testCurrentNFTMetadata();
        
        // Show expected results after deployment
        showExpectedResults();
    }

    function testTierExtraction() internal view {
        console.log("\n=== Testing Tier Extraction ===");
        
        // Extract tier index from user's token ID
        uint256 tierCode = (USER_TOKEN_ID / 10000) % 10;
        uint256 tierIndex = tierCode > 0 ? tierCode - 1 : 0;
        
        console.log("Token ID:", USER_TOKEN_ID);
        console.log("Extracted Tier Code:", tierCode);
        console.log("Extracted Tier Index:", tierIndex);
        console.log("Expected Tier:", "Backstage Pass (Tier 2)");
        
        // Verify this matches expected tier (should be 2 for Backstage Pass)
        if (tierIndex == 2) {
            console.log("SUCCESS: Tier extraction working correctly");
        } else {
            console.log("ERROR: Tier extraction failed");
        }
    }

    function testCurrentNFTMetadata() internal view {
        console.log("\n=== Testing Current NFT Metadata ===");
        
        try TicketNFT(TICKET_NFT).tokenURI(USER_TOKEN_ID) returns (string memory tokenURI) {
            console.log("Current Token URI:");
            console.log(tokenURI);
            
            if (bytes(tokenURI).length > 0) {
                console.log("SUCCESS: Token URI is not empty");
                
                // Check if it's base64 encoded JSON
                if (_startsWith(tokenURI, "data:application/json;base64,")) {
                    console.log("SUCCESS: Token URI is properly formatted base64 JSON");
                } else {
                    console.log("INFO: Token URI format:", _getFirstChars(tokenURI, 50));
                }
            } else {
                console.log("ERROR: Token URI is empty");
            }
        } catch {
            console.log("ERROR: Failed to get token URI");
        }
    }

    function showExpectedResults() internal view {
        console.log("\n=== Expected Results After Tier Image Deployment ===");
        
        // Show what should happen after tier images are set
        uint256 tierIndex = 2; // Backstage Pass
        string memory expectedImageHash = tierImageHashes[tierIndex];
        string memory expectedImageURL = string.concat("https://gateway.pinata.cloud/ipfs/", expectedImageHash);
        
        console.log("Expected Changes:");
        console.log("1. Tier images will be stored in contract via setTierImages()");
        console.log("2. NFT metadata will point to tier-specific image");
        console.log("3. Blockscout will display proper NFT background");
        console.log("");
        console.log("For User's Token (", USER_TOKEN_ID, "):");
        console.log("- Tier Index:", tierIndex);
        console.log("- Tier Name: Backstage Pass");
        console.log("- Expected Image Hash:", expectedImageHash);
        console.log("- Expected Image URL:", expectedImageURL);
        console.log("");
        console.log("Blockscout URL: https://sepolia-blockscout.lisk.com/token/", TICKET_NFT, "/instance/", USER_TOKEN_ID);
    }

    // Helper functions
    function _startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        
        if (strBytes.length < prefixBytes.length) {
            return false;
        }
        
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) {
                return false;
            }
        }
        
        return true;
    }

    function _getFirstChars(string memory str, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length <= length) {
            return str;
        }
        
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = strBytes[i];
        }
        
        return string(result);
    }
}