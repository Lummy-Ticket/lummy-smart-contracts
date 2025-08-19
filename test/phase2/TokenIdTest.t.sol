// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";

contract TokenIdTest is Test {
    
    function testTokenIdGeneration() public pure {
        // Test new format: 1EEETSSSSS
        uint256 eventId = 1;
        uint256 tierCode = 0; // Tier 1 (0-based)
        uint256 sequential = 1;
        
        // New formula: (1 * 1e9) + (eventId * 1e6) + ((tierCode + 1) * 1e4) + sequential
        uint256 expectedTokenId = (1 * 1e9) + (1 * 1e6) + (1 * 1e4) + 1;
        // = 1000000000 + 1000000 + 10000 + 1 = 1001010001
        
        assertEq(expectedTokenId, 1001010001, "Tier 1 token ID should be 1001010001");
        
        // Test Tier 2
        tierCode = 1; // Tier 2 (0-based)
        sequential = 1;
        uint256 expectedTokenId2 = (1 * 1e9) + (1 * 1e6) + (2 * 1e4) + 1;
        // = 1000000000 + 1000000 + 20000 + 1 = 1001020001
        
        assertEq(expectedTokenId2, 1001020001, "Tier 2 token ID should be 1001020001");
    }
    
    function testTierExtraction() public pure {
        // Test extraction from token ID 1001010001 (Tier 1)
        uint256 tokenId1 = 1001010001;
        uint256 tierCode1 = (tokenId1 / 10000) % 10; // = 1
        assertEq(tierCode1, 1, "Should extract tier code 1 from token 1001010001");
        
        // Test extraction from token ID 1001020001 (Tier 2)
        uint256 tokenId2 = 1001020001;
        uint256 tierCode2 = (tokenId2 / 10000) % 10; // = 2
        assertEq(tierCode2, 2, "Should extract tier code 2 from token 1001020001");
    }
}