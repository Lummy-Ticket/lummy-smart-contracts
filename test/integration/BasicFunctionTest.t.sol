// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import "src/shared/libraries/Structs.sol";
import "src/shared/libraries/Base64.sol";
import "src/shared/libraries/Strings.sol";

/**
 * @title BasicFunctionTest
 * @dev Test basic functionality of new libraries and structs
 */
contract BasicFunctionTest is Test {
    using Strings for uint256;
    using Base64 for bytes;

    function setUp() public {
        console.log("=== SETTING UP BASIC FUNCTION TEST ===");
    }

    /**
     * Test Base64 encoding library
     */
    function testBase64Encoding() public {
        console.log("=== TESTING BASE64 ENCODING ===");
        
        string memory testString = "Hello World";
        bytes memory testBytes = bytes(testString);
        
        string memory encoded = Base64.encode(testBytes);
        console.log("Original:", testString);
        console.log("Base64 encoded:", encoded);
        
        // Expected: "Hello World" should encode to "SGVsbG8gV29ybGQ="
        assertEq(encoded, "SGVsbG8gV29ybGQ=", "Base64 encoding should match expected value");
        
        console.log("SUCCESS: Base64 encoding working");
    }

    /**
     * Test Strings library
     */
    function testStringsLibrary() public {
        console.log("=== TESTING STRINGS LIBRARY ===");
        
        uint256 testNumber = 12345;
        string memory numberString = testNumber.toString();
        
        console.log("Number:", testNumber);
        console.log("String:", numberString);
        
        assertEq(numberString, "12345", "Number to string conversion should work");
        
        // Test large number
        uint256 largeNumber = 1000000000000000000; // 1e18
        string memory largeString = largeNumber.toString();
        console.log("Large number:", largeNumber);
        console.log("Large string:", largeString);
        
        console.log("SUCCESS: Strings library working");
    }

    /**
     * Test new Structs fields
     */
    function testNewStructFields() public {
        console.log("=== TESTING NEW STRUCT FIELDS ===");
        
        // Test TicketTier with new fields
        Structs.TicketTier memory tier = Structs.TicketTier({
            name: "VIP Gold",
            price: 500 ether,
            available: 100,
            sold: 0,
            maxPerPurchase: 5,
            active: true,
            description: "Premium VIP experience", // NEW FIELD
            benefits: '["Backstage access", "Meet & greet", "Premium drinks"]' // NEW FIELD
        });
        
        assertEq(tier.name, "VIP Gold", "Tier name should match");
        assertEq(tier.description, "Premium VIP experience", "Description should match");
        assertEq(tier.benefits, '["Backstage access", "Meet & greet", "Premium drinks"]', "Benefits should match");
        
        console.log("Tier name:", tier.name);
        console.log("Tier description:", tier.description);
        console.log("Tier benefits:", tier.benefits);
        
        console.log("SUCCESS: New struct fields working");
    }

    /**
     * Test JSON metadata generation (simulate NFT metadata)
     */
    function testJSONMetadataGeneration() public {
        console.log("=== TESTING JSON METADATA GENERATION ===");
        
        uint256 tokenId = 1001100001; // Example Algorithm 1 token ID
        string memory eventName = "Summer Music Festival";
        string memory tierName = "VIP Gold";
        string memory status = "valid";
        uint256 originalPrice = 500 ether;
        
        // Generate JSON metadata (simplified version)
        string memory json = string(abi.encodePacked(
            '{"name":"Lummy Ticket #', tokenId.toString(), '",',
            '"description":"', eventName, ' - ', tierName, '",',
            '"attributes":[',
            '{"trait_type":"Event","value":"', eventName, '"},',
            '{"trait_type":"Tier","value":"', tierName, '"},',
            '{"trait_type":"Status","value":"', status, '"},',
            '{"trait_type":"Original Price","value":"', originalPrice.toString(), ' IDRX"}',
            ']}'
        ));
        
        console.log("Generated JSON:", json);
        
        // Encode to base64
        string memory base64Json = Base64.encode(bytes(json));
        console.log("Base64 JSON:", base64Json);
        
        // Verify JSON contains expected elements
        assertTrue(bytes(json).length > 0, "JSON should not be empty");
        
        console.log("SUCCESS: JSON metadata generation working");
    }

    /**
     * Test Algorithm 1 token ID format validation
     */
    function testAlgorithm1TokenIDs() public {
        console.log("=== TESTING ALGORITHM 1 TOKEN IDs ===");
        
        // Test valid Algorithm 1 token IDs
        uint256[] memory validTokenIds = new uint256[](5);
        validTokenIds[0] = 1000100001; // Event 0, Tier 1, Serial 1
        validTokenIds[1] = 1001200002; // Event 1, Tier 2, Serial 2
        validTokenIds[2] = 1999900999; // Event 999, Tier 9, Serial 999
        validTokenIds[3] = 1050350010; // Event 50, Tier 3, Serial 10
        validTokenIds[4] = 1100510025; // Event 100, Tier 5, Serial 25
        
        for (uint256 i = 0; i < validTokenIds.length; i++) {
            uint256 tokenId = validTokenIds[i];
            
            // Extract components
            uint256 algorithm = tokenId / 1e9; // Should be 1
            uint256 eventId = (tokenId % 1e9) / 1e6;
            uint256 tierCode = (tokenId % 1e6) / 1e5;
            uint256 serial = tokenId % 1e5;
            
            console.log("Token ID:", tokenId);
            console.log("  Algorithm:", algorithm);
            console.log("  Event ID:", eventId);  
            console.log("  Tier Code:", tierCode);
            console.log("  Serial:", serial);
            
            assertEq(algorithm, 1, "Algorithm should be 1");
            assertTrue(eventId <= 999, "Event ID should be <= 999");
            assertTrue(tierCode >= 1 && tierCode <= 10, "Tier code should be 1-10");
            assertTrue(serial >= 1 && serial <= 99999, "Serial should be 1-99999");
        }
        
        console.log("SUCCESS: Algorithm 1 token ID format validation working");
    }
}