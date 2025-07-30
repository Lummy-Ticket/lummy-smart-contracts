// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Just the interfaces we need
interface IDiamond {
    function addTicketTier(string memory, uint256, uint256, uint256) external;
    function getRoleHierarchy() external view returns (string[] memory);
    function getRevenueStats() external view returns (uint256, uint256);
    function setResaleRules(uint256, uint256, bool, uint256) external;
    function getTierCount() external view returns (uint256);
}

contract DiamondDebugTest is Test {
    address constant DIAMOND = 0x15E50897ca9028A804825a42608711be31C62A70;
    
    function testDebugFunctionSelectors() public {
        console.log("=== DEBUGGING FUNCTION SELECTORS ===");
        
        // Test addTicketTier selector
        bytes4 addTierSelector = bytes4(keccak256("addTicketTier(string,uint256,uint256,uint256)"));
        console.log("addTicketTier selector:", vm.toString(addTierSelector));
        
        // Test getRoleHierarchy selector  
        bytes4 getRoleSelector = bytes4(keccak256("getRoleHierarchy()"));
        console.log("getRoleHierarchy selector:", vm.toString(getRoleSelector));
        
        // Test getRevenueStats selector
        bytes4 getRevenueSelector = bytes4(keccak256("getRevenueStats()"));
        console.log("getRevenueStats selector:", vm.toString(getRevenueSelector));
        
        // Test setResaleRules selector
        bytes4 setResaleSelector = bytes4(keccak256("setResaleRules(uint256,uint256,bool,uint256)"));
        console.log("setResaleRules selector:", vm.toString(setResaleSelector));
    }
    
    function testFacetInfo() public {
        console.log("=== CHECKING FACET INFO ===");
        
        // Get all facets from deployed diamond
        (bool success, bytes memory data) = DIAMOND.staticcall(abi.encodeWithSignature("facetAddresses()"));
        
        if (success) {
            console.log("facetAddresses call successful, data length:", data.length);
        } else {
            console.log("facetAddresses call failed");
        }
    }
    
    function testDirectCalls() public {
        console.log("=== TESTING DIRECT CALLS ===");
        
        // Test with actual deployed diamond
        vm.createSelectFork("https://rpc.sepolia-api.lisk.com");
        
        // Try calling functions directly
        (bool success1,) = DIAMOND.staticcall(abi.encodeWithSignature("getRoleHierarchy()"));
        console.log("getRoleHierarchy direct call success:", success1);
        
        (bool success2,) = DIAMOND.staticcall(abi.encodeWithSignature("getRevenueStats()"));
        console.log("getRevenueStats direct call success:", success2);
        
        (bool success3,) = DIAMOND.staticcall(abi.encodeWithSignature("getTierCount()"));
        console.log("getTierCount direct call success:", success3);
    }
}