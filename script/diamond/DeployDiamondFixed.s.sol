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

/// @title DeployDiamondFixed - Complete Diamond deployment with correct function selectors
/// @notice Deploys Diamond with auto-extracted selectors from actual contract ABIs
contract DeployDiamondFixed is Script {
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
        
        console2.log("=== DEPLOYING FIXED DIAMOND ===");
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

        console2.log("\n3. Preparing diamond cuts with CORRECT selectors...");
        
        // Prepare complete diamond cuts with CORRECT selectors
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
    // CORRECT SELECTOR GENERATION FUNCTIONS  
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
        
        // CORRECT selectors from forge inspect EventCoreFacet
        selectors[0] = 0x950c64ba; // addTicketTier(string,uint256,uint256,uint256)
        selectors[1] = 0xfb6c9537; // cancelEvent()
        selectors[2] = 0x6d00fa68; // getEventInfo()
        selectors[3] = 0xb75b25ec; // getEventStatus()
        selectors[4] = 0x9229b919; // getResaleRules()
        selectors[5] = 0x35882e7e; // getTicketNFT()
        selectors[6] = 0x01fe9913; // getTicketTier(uint256)
        selectors[7] = 0x67184e28; // getTierCount()
        selectors[8] = 0x09a31ea0; // initialize(address,string,string,uint256,string,string)
        selectors[9] = 0x572b6c05; // isTrustedForwarder(address)
        selectors[10] = 0x45298e51; // lockAlgorithm()
        selectors[11] = 0xf191830b; // markEventCompleted()
        selectors[12] = 0x60391df9; // setAlgorithm1(bool,uint256)
        selectors[13] = 0xa1711628; // setResaleRules(uint256,uint256,bool,uint256)
        selectors[14] = 0x48c4ea19; // setTicketNFT(address,address,address)
        selectors[15] = 0x7da0a877; // trustedForwarder()
        selectors[16] = 0xbf3f6450; // updateTicketTier(uint256,string,uint256,uint256,uint256)

        return selectors;
    }

    function _getTicketPurchaseSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](12); // Added 3 new platform fee functions
        
        // CORRECT selectors from forge inspect TicketPurchaseFacet (without duplicates)
        selectors[0] = 0x70e5deb9; // emergencyRefund(uint256)
        selectors[1] = 0xde165fec; // getOrganizerEscrow(address)
        selectors[2] = 0xac18992c; // getRevenueStats()
        selectors[3] = 0x4049d182; // getTierSalesCount(uint256)
        selectors[4] = 0x91b96b63; // getUserPurchaseCount(address)
        selectors[5] = 0x3878c5ef; // processRefund(address,uint256)
        selectors[6] = 0xbdbbb0cb; // purchaseTicket(uint256,uint256)
        selectors[7] = 0x24abf09a; // ticketExists(uint256)
        selectors[8] = 0x23771b86; // withdrawOrganizerFunds()
        // NEW: Platform fee management functions
        selectors[9] = 0x03cb93cf; // getPlatformFeesBalance()
        selectors[10] = 0x12b26271; // getTotalPlatformFeesCollected()
        selectors[11] = 0xd0b7830b; // withdrawPlatformFees()
        // Note: isTrustedForwarder & trustedForwarder removed (duplicates with EventCore)

        return selectors;
    }

    function _getMarketplaceSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](12); // Removed duplicates
        
        // CORRECT selectors from forge inspect MarketplaceFacet (without duplicates)
        selectors[0] = 0xc42ab7d8; // calculateResaleFees(uint256)
        selectors[1] = 0x38475934; // cancelResaleListing(uint256)
        selectors[2] = 0x87c35bc0; // getActiveListings()
        selectors[3] = 0x107a274a; // getListing(uint256)
        selectors[4] = 0x05aaff31; // getMaxResalePrice(uint256)
        selectors[5] = 0xe1ad5c08; // getTokenMarketplaceStats(uint256)
        selectors[6] = 0xca9aea1e; // getTotalMarketplaceVolume()
        selectors[7] = 0xaad25f1f; // getUserResaleRevenue(address)
        selectors[8] = 0x879b8908; // isListedForResale(uint256)
        selectors[9] = 0x6053b0ef; // listTicketForResale(uint256,uint256)
        selectors[10] = 0x3fc4a060; // purchaseResaleTicket(uint256)
        selectors[11] = 0x72b77cba; // updateResaleSettings(bool,bool)
        // Note: isTrustedForwarder & trustedForwarder removed (duplicates with EventCore)

        return selectors;
    }

    function _getStaffManagementSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](12); // Removed duplicates
        
        // CORRECT selectors from forge inspect StaffManagementFacet (without duplicates)
        selectors[0] = 0x522e4c8a; // addStaff(address)
        selectors[1] = 0x40399cb7; // addStaffWithRole(address,uint8)
        selectors[2] = 0x3cf00356; // batchUpdateTicketStatus(uint256[])
        selectors[3] = 0x032e0868; // getAllStaff()
        selectors[4] = 0xead00b3a; // getRoleHierarchy()
        selectors[5] = 0x5594c4d1; // getStaffRole(address)
        selectors[6] = 0x084940bf; // hasStaffRole(address,uint8)
        selectors[7] = 0xcb510e97; // isStaff(address)
        selectors[8] = 0xc4522c92; // removeStaff(address)
        selectors[9] = 0xa2483c3d; // removeStaffRole(address)
        selectors[10] = 0x87e6a8c8; // updateTicketStatus(uint256)
        selectors[11] = 0x054ae7df; // validateTicket(uint256)
        // Note: isTrustedForwarder & trustedForwarder removed (duplicates with EventCore)

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
        console2.log("\n=== TOTAL FUNCTIONS ===");
        console2.log("- DiamondCut: 1 functions");
        console2.log("- DiamondLoupe: 5 functions");
        console2.log("- Ownership: 2 functions");
        console2.log("- EventCore: 17 functions");
        console2.log("- TicketPurchase: 12 functions"); // Added 3 platform fee functions
        console2.log("- Marketplace: 12 functions");
        console2.log("- StaffManagement: 12 functions");
        console2.log("TOTAL: 61 unique functions"); // Updated total
    }

    function _printTestInstructions(DeploymentResult memory result) internal view {
        console2.log("\n=== TEST INSTRUCTIONS ===");
        console2.log("1. All missing functions should now be available!");
        console2.log("\n2. Test previously missing functions:");
        console2.log("   cast call", result.diamond, "'getTierCount()' --rpc-url $RPC_URL");
        console2.log("   cast call", result.diamond, "'getRoleHierarchy()' --rpc-url $RPC_URL");
        console2.log("   cast call", result.diamond, "'getRevenueStats()' --rpc-url $RPC_URL");
        console2.log("   cast call", result.diamond, "'getActiveListings()' --rpc-url $RPC_URL");
        
        console2.log("\n3. Block Explorer:", "https://sepolia-blockscout.lisk.com/address/", result.diamond);
    }
}