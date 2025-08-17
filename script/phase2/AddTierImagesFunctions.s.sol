// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../../src/diamond/interfaces/IDiamondCut.sol";
import "../../src/diamond/facets/DiamondCutFacet.sol";

contract AddTierImagesFunctions is Script {
    address constant DIAMOND_LUMMY = 0x53324e40e7e0977e39a2ea41a5d2e4f60401e5c3;
    address constant EVENT_CORE_FACET = 0x654b175b69c42c15851d50790e8b4f0d91874abc;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Function selectors for tier image functions
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = bytes4(keccak256("setTierImages(string[])"));
        selectors[1] = bytes4(keccak256("getTierImageHash(uint256)"));
        selectors[2] = bytes4(keccak256("getAllTierImageHashes()"));
        selectors[3] = bytes4(keccak256("setTierImageHash(uint256,string)"));
        selectors[4] = bytes4(keccak256("getTierImageCount()"));
        
        console.log("Adding tier image functions to Diamond...");
        console.log("Target Diamond:", DIAMOND_LUMMY);
        console.log("EventCoreFacet:", EVENT_CORE_FACET);
        console.log("setTierImages selector:", vm.toString(selectors[0]));
        
        // Create DiamondCut struct
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: EVENT_CORE_FACET,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
        
        DiamondCutFacet diamondCut = DiamondCutFacet(DIAMOND_LUMMY);
        
        try diamondCut.diamondCut(cuts, address(0), "") {
            console.log("SUCCESS: Tier image functions added to Diamond!");
            
            // Test the functions
            console.log("Testing setTierImages function...");
            string[] memory testHashes = new string[](2);
            testHashes[0] = "QmTest1";
            testHashes[1] = "QmTest2";
            
            // This should now work
            (bool success, ) = DIAMOND_LUMMY.call(
                abi.encodeWithSelector(selectors[0], testHashes)
            );
            
            if (success) {
                console.log("SUCCESS: setTierImages function working!");
            } else {
                console.log("WARNING: setTierImages function still not working");
            }
            
        } catch Error(string memory reason) {
            console.log("FAILED: Error adding tier image functions:");
            console.log("Reason:", reason);
        }
        
        vm.stopBroadcast();
    }
}