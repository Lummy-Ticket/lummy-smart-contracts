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
import {TicketNFT} from "src/shared/contracts/TicketNFT.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "src/diamond/interfaces/IDiamondLoupe.sol";
import {MockIDRX} from "src/shared/contracts/MockIDRX.sol";
import {SimpleForwarder} from "src/shared/contracts/SimpleForwarder.sol";

/// @title DeployComplete - Complete Diamond deployment with TicketNFT integration
/// @notice Deploys Diamond, TicketNFT, and sets up proper connections
contract DeployComplete is Script {
    struct DeploymentResult {
        address diamond;
        address ticketNFT;
        address mockIDRX;
        address trustedForwarder;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("=== DEPLOYING COMPLETE DIAMOND WITH TICKET NFT ===");
        console2.log("Deployer:", deployer);
        console2.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        DeploymentResult memory result = _deployAll(deployer);
        
        vm.stopBroadcast();

        _printResults(result);
    }

    function _deployAll(address deployer) internal returns (DeploymentResult memory result) {
        console2.log("\n1. Deploying supporting contracts...");
        
        // Deploy MockIDRX
        result.mockIDRX = address(new MockIDRX());
        console2.log("MockIDRX:", result.mockIDRX);
        
        // Deploy SimpleForwarder
        result.trustedForwarder = address(new SimpleForwarder(deployer));
        console2.log("SimpleForwarder:", result.trustedForwarder);
        
        // Deploy TicketNFT FIRST
        result.ticketNFT = address(new TicketNFT(result.trustedForwarder));
        console2.log("TicketNFT:", result.ticketNFT);

        console2.log("\n2. Deploying Diamond facets...");
        
        // Deploy all facets
        address diamondCutFacet = address(new DiamondCutFacet());
        address diamondLoupeFacet = address(new DiamondLoupeFacet());
        address ownershipFacet = address(new OwnershipFacet());
        address eventCoreFacet = address(new EventCoreFacet(result.trustedForwarder));
        address ticketPurchaseFacet = address(new TicketPurchaseFacet(result.trustedForwarder));
        address marketplaceFacet = address(new MarketplaceFacet(result.trustedForwarder));
        address staffManagementFacet = address(new StaffManagementFacet(result.trustedForwarder));

        console2.log("All facets deployed successfully");

        console2.log("\n3. Preparing diamond cuts...");
        
        // Prepare complete diamond cuts
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](7);
        
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: diamondCutFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getDiamondCutSelectors()
        });
        
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: diamondLoupeFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getDiamondLoupeSelectors()
        });
        
        cuts[2] = IDiamondCut.FacetCut({
            facetAddress: ownershipFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getOwnershipSelectors()
        });
        
        cuts[3] = IDiamondCut.FacetCut({
            facetAddress: eventCoreFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getEventCoreSelectors()
        });
        
        cuts[4] = IDiamondCut.FacetCut({
            facetAddress: ticketPurchaseFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getTicketPurchaseSelectors()
        });
        
        cuts[5] = IDiamondCut.FacetCut({
            facetAddress: marketplaceFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getMarketplaceSelectors()
        });
        
        cuts[6] = IDiamondCut.FacetCut({
            facetAddress: staffManagementFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getStaffManagementSelectors()
        });

        console2.log("\n4. Deploying Diamond...");
        result.diamond = address(new DiamondLummy(deployer, cuts));
        console2.log("Diamond deployed at:", result.diamond);

        console2.log("\n5. Setting up TicketNFT in Diamond...");
        // Initialize TicketNFT with event contract = Diamond
        TicketNFT(result.ticketNFT).initialize("Lummy Event Tickets", "LUMMY", result.diamond);
        console2.log("TicketNFT initialized with Diamond as event contract");
        
        // Set TicketNFT in Diamond (factory is deployer initially)
        EventCoreFacet(result.diamond).setTicketNFT(
            result.ticketNFT,
            result.mockIDRX,
            deployer // Platform fee receiver
        );
        console2.log("TicketNFT set in Diamond successfully");

        // Verify setup
        address nftAddress = EventCoreFacet(result.diamond).getTicketNFT();
        console2.log("Verification - getTicketNFT():", nftAddress);
        require(nftAddress == result.ticketNFT, "TicketNFT setup failed");

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
        selectors[4] = 0x01ffc9a7; // supportsInterface(bytes4)
        return selectors;
    }

    function _getOwnershipSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = 0x8da5cb5b; // owner()
        selectors[1] = 0xf2fde38b; // transferOwnership(address)
        return selectors;
    }

    function _getEventCoreSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](24); // Updated from 19 to 24
        selectors[0] = 0x65f0a422; // addTicketTier(string,uint256,uint256,uint256,string,string) - UPDATED
        selectors[1] = 0xfb6c9537; // cancelEvent()
        selectors[2] = 0x363053a5; // clearAllTiers() - NEW FUNCTION
        selectors[3] = 0x6d00fa68; // getEventInfo()
        selectors[4] = 0xb75b25ec; // getEventStatus()
        selectors[5] = 0xc58241cc; // getIPFSMetadata() - NEW FUNCTION  
        selectors[6] = 0x9229b919; // getResaleRules()
        selectors[7] = 0x35882e7e; // getTicketNFT()
        selectors[8] = 0x01fe9913; // getTicketTier(uint256)
        selectors[9] = 0x67184e28; // getTierCount()
        selectors[10] = 0x10c22216; // initialize(address,string,string,uint256,string,string,string) - UPDATED
        selectors[11] = 0x572b6c05; // isTrustedForwarder(address)
        selectors[12] = 0x45298e51; // lockAlgorithm()
        selectors[13] = 0xf191830b; // markEventCompleted()
        selectors[14] = 0x60391df9; // setAlgorithm1(bool,uint256)
        selectors[15] = 0xa1711628; // setResaleRules(uint256,uint256,bool,uint256)
        selectors[16] = 0x48c4ea19; // setTicketNFT(address,address,address)
        selectors[17] = 0x7da0a877; // trustedForwarder()
        selectors[18] = 0x66ec5a57; // updateTicketTier(uint256,string,uint256,uint256,uint256,string,string) - UPDATED
        // Tier Image Functions - NEW
        selectors[19] = 0xecfe5a5e; // setTierImages(string[])
        selectors[20] = 0x819ad6a5; // getTierImageHash(uint256)
        selectors[21] = 0x263e9970; // getAllTierImageHashes()
        selectors[22] = 0x8b9f125f; // setTierImageHash(uint256,string)
        selectors[23] = 0xb3ff9da4; // getTierImageCount()
        return selectors;
    }

    function _getTicketPurchaseSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = 0x70e5deb9; // emergencyRefund(uint256)
        selectors[1] = 0xde165fec; // getOrganizerEscrow(address)
        selectors[2] = 0xac18992c; // getRevenueStats()
        selectors[3] = 0x4049d182; // getTierSalesCount(uint256)
        selectors[4] = 0x91b96b63; // getUserPurchaseCount(address)
        selectors[5] = 0x3878c5ef; // processRefund(address,uint256)
        selectors[6] = 0xbdbbb0cb; // purchaseTicket(uint256,uint256)
        selectors[7] = 0x24abf09a; // ticketExists(uint256)
        selectors[8] = 0x23771b86; // withdrawOrganizerFunds()
        selectors[9] = 0x03cb93cf; // getPlatformFeesBalance()
        selectors[10] = 0x12b26271; // getTotalPlatformFeesCollected()
        selectors[11] = 0xd0b7830b; // withdrawPlatformFees()
        return selectors;
    }

    function _getMarketplaceSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](12);
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
        return selectors;
    }

    function _getStaffManagementSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = 0x40399cb7; // addStaff(address,uint8)
        selectors[1] = 0xa2483c3d; // checkInAttendee(uint256,string)
        selectors[2] = 0x522e4c8a; // getAllStaff()
        selectors[3] = 0xc4522c92; // getRoleHierarchy()
        selectors[4] = 0x87e6a8c8; // getStaffRole(address)
        selectors[5] = 0x3cf00356; // getTicketCheckInStatus(uint256)
        selectors[6] = 0x054ae7df; // removeStaff(address)
        selectors[7] = 0x5594c4d1; // updateStaffRole(address,uint8)
        selectors[8] = 0x084940bf; // validateTicket(uint256,string)
        return selectors;
    }

    function _printResults(DeploymentResult memory result) internal view {
        console2.log("\n=== DEPLOYMENT COMPLETE ===");
        console2.log("Diamond Address:", result.diamond);
        console2.log("TicketNFT Address:", result.ticketNFT);
        console2.log("MockIDRX:", result.mockIDRX);
        console2.log("TrustedForwarder:", result.trustedForwarder);
        
        console2.log("\n=== UPDATE FRONTEND ===");
        console2.log("Update constants.ts:");
        console2.log("DiamondLummy:", result.diamond);
        console2.log("MockIDRX:", result.mockIDRX);
        console2.log("TrustedForwarder:", result.trustedForwarder);
        
        console2.log("\n=== VERIFICATION COMMANDS ===");
        console2.log("Test TicketNFT connection:");
        console2.log("cast call", result.diamond, "'getTicketNFT()' --rpc-url https://rpc.sepolia-api.lisk.com");
        console2.log("Expected result:", result.ticketNFT);
    }
}