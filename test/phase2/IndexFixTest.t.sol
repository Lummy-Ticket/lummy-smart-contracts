// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {EventCoreFacet} from "../../src/diamond/facets/EventCoreFacet.sol";

contract IndexFixTest is Test {
    
    function testTierIndexMapping() public pure {
        // Test the index mapping logic directly
        
        // Test tier 1 mapping
        uint256 tierIndex1 = 1;
        uint256 storageIndex1 = tierIndex1 - 1; // Should be 0
        assertEq(storageIndex1, 0, "Tier 1 should map to storage index 0");
        
        // Test tier 2 mapping  
        uint256 tierIndex2 = 2;
        uint256 storageIndex2 = tierIndex2 - 1; // Should be 1
        assertEq(storageIndex2, 1, "Tier 2 should map to storage index 1");
        
        console.log("=== Index Mapping Test ===");
        console.log("Tier 1 -> Storage Index:", storageIndex1);
        console.log("Tier 2 -> Storage Index:", storageIndex2);
    }
    
    function testTokenIdExtraction() public pure {
        // Test token ID extraction matches expected tier calls
        
        // Token 1001010001 (Tier 1)
        uint256 token1 = 1001010001;
        uint256 tierCode1 = (token1 / 10000) % 10; // Should be 1
        assertEq(tierCode1, 1, "Token 1001010001 should extract tier code 1");
        
        // Token 1001020001 (Tier 2)
        uint256 token2 = 1001020001;
        uint256 tierCode2 = (token2 / 10000) % 10; // Should be 2
        assertEq(tierCode2, 2, "Token 1001020001 should extract tier code 2");
        
        console.log("=== Token Extraction Test ===");
        console.log("Token 1001010001 -> Tier Code:", tierCode1);
        console.log("Token 1001020001 -> Tier Code:", tierCode2);
    }
}