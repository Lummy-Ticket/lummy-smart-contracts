// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console2} from "forge-std/Script.sol";
import {TicketNFT} from "src/shared/contracts/TicketNFT.sol";

/// @title DeployTicketNFTOnly - Deploy TicketNFT contract only
/// @notice Simple deployment of TicketNFT for use with existing Diamond
contract DeployTicketNFTOnly is Script {
    address constant TRUSTED_FORWARDER = 0xA86b473A3f16146c7981015bD191F29aF7894988;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("=== DEPLOYING TICKET NFT ONLY ===");
        console2.log("Deployer:", deployer);
        console2.log("Balance:", deployer.balance);
        console2.log("Trusted Forwarder:", TRUSTED_FORWARDER);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy TicketNFT
        console2.log("\nDeploying TicketNFT...");
        TicketNFT ticketNFT = new TicketNFT(TRUSTED_FORWARDER);
        
        vm.stopBroadcast();

        console2.log("\n=== DEPLOYMENT COMPLETE ===");
        console2.log("TicketNFT Address:", address(ticketNFT));
        
        console2.log("\n=== NEXT STEPS ===");
        console2.log("Now call setTicketNFT on Diamond with:");
        console2.log("Diamond Address: 0x5677c194A7efca97853Cb434Aa59252A0c364074");
        console2.log("TicketNFT Address:", address(ticketNFT));
        console2.log("IDRX Address: 0xBAc0800a4F278853973669B6F4Ec70ae03be1184");
        console2.log("Platform Fee Receiver: 0x580B01f8CDf7606723c3BE0dD2AaD058F5aECa3d");
        
        console2.log("\nCast command:");
        console2.log("cast send 0x5677c194A7efca97853Cb434Aa59252A0c364074 \\");
        console2.log("  'setTicketNFT(address,address,address)' \\");
        console2.log("  ", address(ticketNFT), " \\");
        console2.log("  0xBAc0800a4F278853973669B6F4Ec70ae03be1184 \\");
        console2.log("  0x580B01f8CDf7606723c3BE0dD2AaD058F5aECa3d \\");
        console2.log("  --rpc-url https://rpc.sepolia-api.lisk.com \\");
        console2.log("  --private-key $PRIVATE_KEY");
    }
}