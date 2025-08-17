// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../../src/diamond/facets/EventCoreFacet.sol";

contract SetTierImages is Script {
    address constant DIAMOND_LUMMY = 0xE91B4c3ADa9193A513f7f9A808ee04fEf6b4Ef8D;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Example tier image IPFS hashes - replace these with your actual hashes
        string[] memory tierImageHashes = new string[](3);
        
        // Use placeholder images for testing - replace with real hashes if available
        tierImageHashes[0] = "QmNP3kX8cNVMpGGhwzwjqFVzAYmGzHdLqDdJSzrGbpzEcS"; // Tier 0 placeholder
        tierImageHashes[1] = "QmNP3kX8cNVMpGGhwzwjqFVzAYmGzHdLqDdJSzrGbpzEcS"; // Tier 1 placeholder  
        tierImageHashes[2] = "QmNP3kX8cNVMpGGhwzwjqFVzAYmGzHdLqDdJSzrGbpzEcS"; // Tier 2 placeholder
        
        EventCoreFacet eventCore = EventCoreFacet(DIAMOND_LUMMY);
        
        console.log("Setting tier images...");
        console.log("Tier 0 hash:", tierImageHashes[0]);
        console.log("Tier 1 hash:", tierImageHashes[1]);
        console.log("Tier 2 hash:", tierImageHashes[2]);
        
        try eventCore.setTierImages(tierImageHashes) {
            console.log("SUCCESS: Tier images set successfully!");
            
            // Verify the setup
            uint256 count = eventCore.getTierImageCount();
            console.log("Total tier images count:", count);
            
            for (uint256 i = 0; i < count; i++) {
                string memory hash = eventCore.getTierImageHash(i);
                console.log("Tier", i, "image hash:", hash);
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Error setting tier images:");
            console.log("Reason:", reason);
        }
        
        vm.stopBroadcast();
    }
}