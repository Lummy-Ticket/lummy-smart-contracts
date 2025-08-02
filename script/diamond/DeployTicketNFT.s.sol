// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console2} from "forge-std/Script.sol";
import {TicketNFT} from "src/shared/contracts/TicketNFT.sol";
import {EventCoreFacet} from "src/diamond/facets/EventCoreFacet.sol";

/// @title DeployTicketNFT - Deploy and setup TicketNFT for existing Diamond
/// @notice Deploys TicketNFT and sets it in existing Diamond contract
contract DeployTicketNFT is Script {
    address constant DIAMOND_ADDRESS = 0x5677c194A7efca97853Cb434Aa59252A0c364074;
    address constant TRUSTED_FORWARDER = 0xA86b473A3f16146c7981015bD191F29aF7894988;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("=== DEPLOYING TICKET NFT FOR EXISTING DIAMOND ===");
        console2.log("Diamond Address:", DIAMOND_ADDRESS);
        console2.log("Deployer:", deployer);
        console2.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy TicketNFT
        console2.log("Deploying TicketNFT...");
        TicketNFT ticketNFT = new TicketNFT(TRUSTED_FORWARDER);
        console2.log("TicketNFT deployed at:", address(ticketNFT));

        // Set TicketNFT in Diamond
        console2.log("Setting TicketNFT in Diamond...");
        EventCoreFacet(DIAMOND_ADDRESS).setTicketNFT(
            address(ticketNFT),
            DIAMOND_ADDRESS, // Diamond as the minter
            TRUSTED_FORWARDER
        );
        console2.log("TicketNFT set in Diamond successfully!");

        vm.stopBroadcast();

        console2.log("\n=== DEPLOYMENT COMPLETE ===");
        console2.log("TicketNFT Address:", address(ticketNFT));
        console2.log("Diamond Address:", DIAMOND_ADDRESS);
        console2.log("\n=== TEST COMMAND ===");
        console2.log("cast call", DIAMOND_ADDRESS, "'getTicketNFT()' --rpc-url https://rpc.sepolia-api.lisk.com");
    }
}