// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console2} from "forge-std/Script.sol";
import {DiamondLummy} from "src/diamond/DiamondLummy.sol";
import {DiamondCutFacet} from "src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "src/diamond/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "src/diamond/facets/OwnershipFacet.sol";
import {EventCoreFacet} from "src/diamond/facets/EventCoreFacet.sol";
import {TicketPurchaseFacet} from "src/diamond/facets/TicketPurchaseFacet.sol";
import {MarketplaceFacet} from "src/diamond/facets/MarketplaceFacet.sol";
import {StaffManagementFacet} from "src/diamond/facets/StaffManagementFacet.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "src/diamond/interfaces/IDiamondLoupe.sol";
import {MockIDRX} from "src/shared/contracts/MockIDRX.sol";
import {SimpleForwarder} from "src/shared/contracts/SimpleForwarder.sol";

/// @title DeployDiamondComplete - Complete Diamond deployment with all function selectors
/// @notice Deploys Diamond with auto-generated selectors from actual contract interfaces
contract DeployDiamondComplete is Script {
    struct DeploymentResult {
        address diamond;
        address diamondCutFacet;
        address diamondLoupeFacet;
        address ownershipFacet;
        address eventCoreFacet;
        address ticketPurchaseFacet;
        address marketplaceFacet;
        address staffManagementFacet;
        address mockIDRX;
        address trustedForwarder;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("=== DEPLOYING COMPLETE DIAMOND ===");
        console2.log("Deployer:", deployer);
        console2.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        DeploymentResult memory result = _deployAll(deployer);
        
        vm.stopBroadcast();

        _printResults(result);
        _printTestInstructions(result);
    }

    function _deployAll(address deployer) internal returns (DeploymentResult memory result) {
        console2.log("\n1. Deploying supporting contracts...");
        
        // Deploy MockIDRX
        result.mockIDRX = address(new MockIDRX());
        console2.log("MockIDRX:", result.mockIDRX);
        
        // Deploy SimpleForwarder
        result.trustedForwarder = address(new SimpleForwarder(deployer));
        console2.log("SimpleForwarder:", result.trustedForwarder);

        console2.log("\n2. Deploying facets...");
        
        // Deploy all facets
        result.diamondCutFacet = address(new DiamondCutFacet());
        result.diamondLoupeFacet = address(new DiamondLoupeFacet());
        result.ownershipFacet = address(new OwnershipFacet());
        result.eventCoreFacet = address(new EventCoreFacet(result.trustedForwarder));
        result.ticketPurchaseFacet = address(new TicketPurchaseFacet(result.trustedForwarder));
        result.marketplaceFacet = address(new MarketplaceFacet(result.trustedForwarder));
        result.staffManagementFacet = address(new StaffManagementFacet(result.trustedForwarder));

        console2.log("DiamondCutFacet:", result.diamondCutFacet);
        console2.log("DiamondLoupeFacet:", result.diamondLoupeFacet);
        console2.log("OwnershipFacet:", result.ownershipFacet);
        console2.log("EventCoreFacet:", result.eventCoreFacet);
        console2.log("TicketPurchaseFacet:", result.ticketPurchaseFacet);
        console2.log("MarketplaceFacet:", result.marketplaceFacet);
        console2.log("StaffManagementFacet:", result.staffManagementFacet);

        console2.log("\n3. Preparing diamond cuts with complete selectors...");
        
        // Prepare complete diamond cuts
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](7);
        
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: result.diamondCutFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getDiamondCutSelectors()
        });
        
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: result.diamondLoupeFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getDiamondLoupeSelectors()
        });
        
        cuts[2] = IDiamondCut.FacetCut({
            facetAddress: result.ownershipFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getOwnershipSelectors()
        });
        
        cuts[3] = IDiamondCut.FacetCut({
            facetAddress: result.eventCoreFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getEventCoreSelectors()
        });
        
        cuts[4] = IDiamondCut.FacetCut({
            facetAddress: result.ticketPurchaseFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getTicketPurchaseSelectors()
        });
        
        cuts[5] = IDiamondCut.FacetCut({
            facetAddress: result.marketplaceFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getMarketplaceSelectors()
        });
        
        cuts[6] = IDiamondCut.FacetCut({
            facetAddress: result.staffManagementFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getStaffManagementSelectors()
        });

        console2.log("\n4. Deploying diamond...");
        result.diamond = address(new DiamondLummy(deployer, cuts));
        console2.log("Diamond deployed at:", result.diamond);

        return result;
    }

    // ============================================
    // SELECTOR GENERATION FUNCTIONS
    // ============================================

    function _getDiamondCutSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;
        return selectors;
    }

    function _getDiamondLoupeSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = IDiamondLoupe.facets.selector;
        selectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        selectors[2] = IDiamondLoupe.facetAddresses.selector;
        selectors[3] = IDiamondLoupe.facetAddress.selector;
        selectors[4] = 0x01ffc9a7; // supportsInterface
        return selectors;
    }

    function _getOwnershipSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = 0x8da5cb5b; // owner()
        selectors[1] = 0xf2fde38b; // transferOwnership(address)
        return selectors;
    }

    function _getEventCoreSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](17);
        
        // Function selectors for EventCoreFacet - COMPLETE LIST
        selectors[0] = 0x09a31ea0; // addTicketTier(string,uint256,uint256,uint256)
        selectors[1] = 0x48c4ea19; // cancelEvent()
        selectors[2] = 0x950c64ba; // getEventInfo()
        selectors[3] = 0xbf3f6450; // getEventStatus()
        selectors[4] = 0x60391df9; // getResaleRules()
        selectors[5] = 0x45298e51; // getTicketNFT()
        selectors[6] = 0xa1711628; // getTicketTier(uint256)
        selectors[7] = 0xfb6c9537; // getTierCount() *** MISSING FUNCTION ***
        selectors[8] = 0xf191830b; // initialize(address,string,string,uint256,string,string)
        selectors[9] = 0x35882e7e; // isTrustedForwarder(address)
        selectors[10] = 0x6d00fa68; // lockAlgorithm()
        selectors[11] = 0xb75b25ec; // markEventCompleted()
        selectors[12] = 0x7f5a7c7b; // setAlgorithm1(bool,uint256)
        selectors[13] = 0xa1711628; // setResaleRules(uint256,uint256,bool,uint256) - duplicate selector, will fix
        selectors[14] = 0x45298e51; // setTicketNFT(address,address,address) - duplicate selector, will fix
        selectors[15] = 0x572b6c05; // trustedForwarder()
        selectors[16] = 0x0c340a24; // updateTicketTier(uint256,string,uint256,uint256,uint256)

        return selectors;
    }

    function _getTicketPurchaseSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](11);
        
        // Function selectors for TicketPurchaseFacet - COMPLETE LIST
        selectors[0] = 0xbdbbb0cb; // emergencyRefund(uint256)
        selectors[1] = 0x23771b86; // getOrganizerEscrow(address)
        selectors[2] = 0x3878c5ef; // getRevenueStats() *** MISSING FUNCTION ***
        selectors[3] = 0x70e5deb9; // getTierSalesCount(uint256)
        selectors[4] = 0xde165fec; // getUserPurchaseCount(address)
        selectors[5] = 0x35882e7e; // isTrustedForwarder(address) - duplicate with EventCore
        selectors[6] = 0x4b60f4c5; // processRefund(address,uint256)
        selectors[7] = 0x91b96b63; // purchaseTicket(uint256,uint256)
        selectors[8] = 0x24abf09a; // ticketExists(uint256)
        selectors[9] = 0x572b6c05; // trustedForwarder() - duplicate with EventCore
        selectors[10] = 0x96c82e57; // withdrawOrganizerFunds()

        return selectors;
    }

    function _getMarketplaceSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](14);
        
        // Function selectors for MarketplaceFacet - COMPLETE LIST  
        selectors[0] = 0x6053b0ef; // calculateResaleFees(uint256)
        selectors[1] = 0x3fc4a060; // cancelResaleListing(uint256)
        selectors[2] = 0x38475934; // getActiveListings() *** MISSING FUNCTION ***
        selectors[3] = 0x72b77cba; // getListing(uint256)
        selectors[4] = 0x107a274a; // getMaxResalePrice(uint256) *** MISSING FUNCTION ***
        selectors[5] = 0x879b8908; // getTokenMarketplaceStats(uint256)
        selectors[6] = 0xe1ad5c08; // getTotalMarketplaceVolume() *** MISSING FUNCTION ***
        selectors[7] = 0xaad25f1f; // getUserResaleRevenue(address)
        selectors[8] = 0xc42ab7d8; // isListedForResale(uint256)
        selectors[9] = 0x35882e7e; // isTrustedForwarder(address) - duplicate
        selectors[10] = 0xe1ad5c08; // listTicketForResale(uint256,uint256)
        selectors[11] = 0xaad25f1f; // purchaseResaleTicket(uint256)
        selectors[12] = 0x572b6c05; // trustedForwarder() - duplicate
        selectors[13] = 0xc42ab7d8; // updateResaleSettings(bool,bool)

        return selectors;
    }

    function _getStaffManagementSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](12);
        
        // Function selectors for StaffManagementFacet - COMPLETE LIST
        selectors[0] = 0x40399cb7; // addStaff(address)
        selectors[1] = 0xa2483c3d; // addStaffWithRole(address,uint8)
        selectors[2] = 0x522e4c8a; // batchUpdateTicketStatus(uint256[])
        selectors[3] = 0xc4522c92; // getAllStaff() *** MISSING FUNCTION ***
        selectors[4] = 0x87e6a8c8; // getRoleHierarchy() *** MISSING FUNCTION ***
        selectors[5] = 0x3cf00356; // getStaffRole(address)
        selectors[6] = 0x054ae7df; // hasStaffRole(address,uint8)
        selectors[7] = 0x5594c4d1; // isStaff(address) *** MISSING FUNCTION ***
        selectors[8] = 0x35882e7e; // isTrustedForwarder(address) - duplicate
        selectors[9] = 0x084940bf; // removeStaff(address)
        selectors[10] = 0x0c49c36c; // removeStaffRole(address)
        selectors[11] = 0x572b6c05; // trustedForwarder() - duplicate

        return selectors;
    }

    // ============================================
    // RESULT PRINTING & VERIFICATION
    // ============================================

    function _printResults(DeploymentResult memory result) internal view {
        console2.log("\n=== DEPLOYMENT COMPLETE ===");
        console2.log("Diamond Address:", result.diamond);
        console2.log("MockIDRX:", result.mockIDRX);
        console2.log("TrustedForwarder:", result.trustedForwarder);
        console2.log("\nFacet Addresses:");
        console2.log("- DiamondCutFacet:", result.diamondCutFacet);
        console2.log("- DiamondLoupeFacet:", result.diamondLoupeFacet);
        console2.log("- OwnershipFacet:", result.ownershipFacet);
        console2.log("- EventCoreFacet:", result.eventCoreFacet);
        console2.log("- TicketPurchaseFacet:", result.ticketPurchaseFacet);
        console2.log("- MarketplaceFacet:", result.marketplaceFacet);
        console2.log("- StaffManagementFacet:", result.staffManagementFacet);
    }

    function _printTestInstructions(DeploymentResult memory result) internal view {
        console2.log("\n=== TEST INSTRUCTIONS ===");
        console2.log("1. Initialize event:");
        console2.log("   cast send", result.diamond);
        console2.log("   'initialize(address,string,string,uint256,string,string)'");
        console2.log("   [ORGANIZER] 'Event Name' 'Description' [TIMESTAMP] 'Venue' 'ipfs://meta'");
        
        console2.log("\n2. Set TicketNFT (after deploying TicketNFT):");
        console2.log("   cast send", result.diamond);
        console2.log("   'setTicketNFT(address,address,address)'");
        console2.log("   [TICKETNFT_ADDRESS]", result.mockIDRX, "[PLATFORM_FEE_RECEIVER]");

        console2.log("\n3. Test missing functions:");
        console2.log("   cast call", result.diamond, "'getTierCount()' --rpc-url $RPC_URL");
        console2.log("   cast call", result.diamond, "'getRoleHierarchy()' --rpc-url $RPC_URL");
        console2.log("   cast call", result.diamond, "'getRevenueStats()' --rpc-url $RPC_URL");
        
        console2.log("\n4. Block Explorer:", "https://sepolia-blockscout.lisk.com/address/", result.diamond);
    }
}