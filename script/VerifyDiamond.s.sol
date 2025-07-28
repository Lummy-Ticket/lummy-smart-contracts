// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console2} from "forge-std/Script.sol";

/// @title VerifyDiamond - Script to verify all deployed contracts
/// @notice Provides contract addresses and constructor args for verification
contract VerifyDiamond is Script {
    
    // Deployed contract addresses
    address constant DIAMOND = 0x15E50897ca9028A804825a42608711be31C62A70;
    address constant DIAMOND_CUT_FACET = 0x6058A6673B9373DB94d620d6E8afc18a0E743aB6;
    address constant DIAMOND_LOUPE_FACET = 0x3f7af2eFF83D0DE7Af6B68fb41abC1BE72a8055e;
    address constant OWNERSHIP_FACET = 0x71d2052ca44183FB58fE1fA9A3585D2348D58Ba6;
    address constant EVENT_CORE_FACET = 0x5E4299F3f600A3737De6a91cca1bC9d998f46245;
    address constant TICKET_PURCHASE_FACET = 0x851b554920F1cC71CA37b36D612871d439F45eC4;
    address constant MARKETPLACE_FACET = 0xe2b3C58ff5d04d7C0059Ea5A964293BdDc10b3ef;
    address constant STAFF_MANAGEMENT_FACET = 0x628f5268789ccB598BaAF52B2d4CB5aA97567b28;
    address constant MOCK_IDRX = 0xb57Cf872ac226e36124d59BA5345734190d31e51;
    address constant TRUSTED_FORWARDER = 0x23fE27ca9A38c041Df477Eb14a5232cCB3fB844f;
    
    // Deployer address
    address constant DEPLOYER = 0x580B01f8CDf7606723c3BE0dD2AaD058F5aECa3d;
    
    function run() external pure {
        console2.log("=== LISK SEPOLIA VERIFICATION COMMANDS ===");
        console2.log("Chain ID: 4202");
        console2.log("RPC URL: https://rpc.sepolia-api.lisk.com");
        console2.log("Explorer: https://sepolia-blockscout.lisk.com");
        console2.log("");
        
        _printSupportingContractsVerification();
        _printFacetVerification();
        _printDiamondVerification();
        _printManualVerificationSteps();
    }
    
    function _printSupportingContractsVerification() internal pure {
        console2.log("=== 1. SUPPORTING CONTRACTS VERIFICATION ===");
        console2.log("");
        
        console2.log("# MockIDRX Token (No constructor args)");
        console2.log("forge verify-contract \\");
        console2.log("  --chain-id 4202 \\");
        console2.log("  --rpc-url https://rpc.sepolia-api.lisk.com \\");
        console2.log("  --etherscan-api-key [YOUR_API_KEY] \\");
        console2.log("  ", vm.toString(MOCK_IDRX), " \\");
        console2.log("  src/core/MockIDRX.sol:MockIDRX");
        console2.log("");
        
        console2.log("# SimpleForwarder (Constructor: address paymaster)");
        console2.log("forge verify-contract \\");
        console2.log("  --chain-id 4202 \\");
        console2.log("  --rpc-url https://rpc.sepolia-api.lisk.com \\");
        console2.log("  --etherscan-api-key [YOUR_API_KEY] \\");
        console2.log("  --constructor-args $(cast abi-encode \"constructor(address)\" ", vm.toString(DEPLOYER), ") \\");
        console2.log("  ", vm.toString(TRUSTED_FORWARDER), " \\");
        console2.log("  src/core/SimpleForwarder.sol:SimpleForwarder");
        console2.log("");
    }
    
    function _printFacetVerification() internal pure {
        console2.log("=== 2. FACETS VERIFICATION ===");
        console2.log("");
        
        console2.log("# DiamondCutFacet (No constructor args)");
        console2.log("forge verify-contract \\");
        console2.log("  --chain-id 4202 \\");
        console2.log("  --rpc-url https://rpc.sepolia-api.lisk.com \\");
        console2.log("  --etherscan-api-key [YOUR_API_KEY] \\");
        console2.log("  ", vm.toString(DIAMOND_CUT_FACET), " \\");
        console2.log("  src/diamond/facets/DiamondCutFacet.sol:DiamondCutFacet");
        console2.log("");
        
        console2.log("# DiamondLoupeFacet (No constructor args)");
        console2.log("forge verify-contract \\");
        console2.log("  --chain-id 4202 \\");
        console2.log("  --rpc-url https://rpc.sepolia-api.lisk.com \\");
        console2.log("  --etherscan-api-key [YOUR_API_KEY] \\");
        console2.log("  ", vm.toString(DIAMOND_LOUPE_FACET), " \\");
        console2.log("  src/diamond/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet");
        console2.log("");
        
        console2.log("# OwnershipFacet (No constructor args)");
        console2.log("forge verify-contract \\");
        console2.log("  --chain-id 4202 \\");
        console2.log("  --rpc-url https://rpc.sepolia-api.lisk.com \\");
        console2.log("  --etherscan-api-key [YOUR_API_KEY] \\");
        console2.log("  ", vm.toString(OWNERSHIP_FACET), " \\");
        console2.log("  src/diamond/facets/OwnershipFacet.sol:OwnershipFacet");
        console2.log("");
        
        console2.log("# EventCoreFacet (Constructor: address trustedForwarder)");
        console2.log("forge verify-contract \\");
        console2.log("  --chain-id 4202 \\");
        console2.log("  --rpc-url https://rpc.sepolia-api.lisk.com \\");
        console2.log("  --etherscan-api-key [YOUR_API_KEY] \\");
        console2.log("  --constructor-args $(cast abi-encode \"constructor(address)\" ", vm.toString(TRUSTED_FORWARDER), ") \\");
        console2.log("  ", vm.toString(EVENT_CORE_FACET), " \\");
        console2.log("  src/diamond/facets/EventCoreFacet.sol:EventCoreFacet");
        console2.log("");
        
        console2.log("# TicketPurchaseFacet (Constructor: address trustedForwarder)");
        console2.log("forge verify-contract \\");
        console2.log("  --chain-id 4202 \\");
        console2.log("  --rpc-url https://rpc.sepolia-api.lisk.com \\");
        console2.log("  --etherscan-api-key [YOUR_API_KEY] \\");
        console2.log("  --constructor-args $(cast abi-encode \"constructor(address)\" ", vm.toString(TRUSTED_FORWARDER), ") \\");
        console2.log("  ", vm.toString(TICKET_PURCHASE_FACET), " \\");
        console2.log("  src/diamond/facets/TicketPurchaseFacet.sol:TicketPurchaseFacet");
        console2.log("");
        
        console2.log("# MarketplaceFacet (Constructor: address trustedForwarder)");
        console2.log("forge verify-contract \\");
        console2.log("  --chain-id 4202 \\");
        console2.log("  --rpc-url https://rpc.sepolia-api.lisk.com \\");
        console2.log("  --etherscan-api-key [YOUR_API_KEY] \\");
        console2.log("  --constructor-args $(cast abi-encode \"constructor(address)\" ", vm.toString(TRUSTED_FORWARDER), ") \\");
        console2.log("  ", vm.toString(MARKETPLACE_FACET), " \\");
        console2.log("  src/diamond/facets/MarketplaceFacet.sol:MarketplaceFacet");
        console2.log("");
        
        console2.log("# StaffManagementFacet (Constructor: address trustedForwarder)");
        console2.log("forge verify-contract \\");
        console2.log("  --chain-id 4202 \\");
        console2.log("  --rpc-url https://rpc.sepolia-api.lisk.com \\");
        console2.log("  --etherscan-api-key [YOUR_API_KEY] \\");
        console2.log("  --constructor-args $(cast abi-encode \"constructor(address)\" ", vm.toString(TRUSTED_FORWARDER), ") \\");
        console2.log("  ", vm.toString(STAFF_MANAGEMENT_FACET), " \\");
        console2.log("  src/diamond/facets/StaffManagementFacet.sol:StaffManagementFacet");
        console2.log("");
    }
    
    function _printDiamondVerification() internal pure {
        console2.log("=== 3. DIAMOND VERIFICATION (COMPLEX) ===");
        console2.log("");
        console2.log("Diamond verification requires complex constructor args.");
        console2.log("The constructor takes (address owner, IDiamondCut.FacetCut[] memory diamondCut)");
        console2.log("");
        console2.log("Diamond Address: ", vm.toString(DIAMOND));
        console2.log("Constructor Args:");
        console2.log("- owner: ", vm.toString(DEPLOYER));
        console2.log("- diamondCut: Array of 7 FacetCut structs");
        console2.log("");
        console2.log("Due to complexity, Diamond verification may need manual approach.");
        console2.log("");
    }
    
    function _printManualVerificationSteps() internal pure {
        console2.log("=== 4. MANUAL VERIFICATION ALTERNATIVE ===");
        console2.log("");
        console2.log("If forge verify fails, use block explorer manual verification:");
        console2.log("");
        console2.log("1. Go to: https://sepolia-blockscout.lisk.com");
        console2.log("2. Search for contract address");
        console2.log("3. Click 'Verify & Publish'");
        console2.log("4. Select 'Via Solidity file'");
        console2.log("5. Upload contract source code");
        console2.log("6. Set compiler version: 0.8.29");
        console2.log("7. Set optimization: Yes (200 runs)");
        console2.log("8. Add constructor arguments if needed");
        console2.log("");
        console2.log("=== 5. TESTING AFTER VERIFICATION ===");
        console2.log("");
        console2.log("# Test Diamond ownership");
        console2.log("cast call ", vm.toString(DIAMOND), " \"owner()\" --rpc-url https://rpc.sepolia-api.lisk.com");
        console2.log("");
        console2.log("# Test facet addresses");
        console2.log("cast call ", vm.toString(DIAMOND), " \"facetAddresses()\" --rpc-url https://rpc.sepolia-api.lisk.com");
        console2.log("");
        console2.log("# Test IDRX balance");
        console2.log("cast call", vm.toString(MOCK_IDRX));
        console2.log("  \"balanceOf(address)\"", vm.toString(DEPLOYER));
        console2.log("  --rpc-url https://rpc.sepolia-api.lisk.com");
        console2.log("");
        console2.log("=====================================");
        console2.log("Replace [YOUR_API_KEY] with actual API key from block explorer");
        console2.log("=====================================");
    }
}