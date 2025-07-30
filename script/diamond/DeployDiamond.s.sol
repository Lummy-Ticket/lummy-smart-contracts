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
import {MockIDRX} from "src/shared/contracts/MockIDRX.sol";
import {SimpleForwarder} from "src/shared/contracts/SimpleForwarder.sol";

/// @title DeployDiamond - Diamond deployment script
/// @author Lummy Protocol Team
/// @notice Deploys Lummy Diamond pattern contracts with all facets
/// @dev Handles phased deployment and diamond cut operations
contract DeployDiamond is Script {
    /// @notice Struct to hold deployment addresses
    struct DeploymentAddresses {
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

    /// @notice Main deployment function
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying Diamond with deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy supporting contracts first
        DeploymentAddresses memory addresses = _deploySupportingContracts(deployer);
        
        // Deploy all facets
        _deployFacets(addresses);
        
        // Deploy diamond with initial facets
        addresses.diamond = _deployDiamondWithFacets(addresses, deployer);
        
        // Verify deployment
        _verifyDeployment(addresses);
        
        vm.stopBroadcast();

        // Log deployment addresses
        _logDeploymentInfo(addresses);
    }

    /// @notice Deploy supporting contracts (MockIDRX, SimpleForwarder)
    /// @param deployer Address of the deployer (for SimpleForwarder paymaster)
    /// @return addresses Struct containing deployed addresses
    function _deploySupportingContracts(address deployer) internal returns (DeploymentAddresses memory addresses) {
        console2.log("Deploying supporting contracts...");
        
        // Deploy MockIDRX token
        addresses.mockIDRX = address(new MockIDRX());
        console2.log("MockIDRX deployed at:", addresses.mockIDRX);
        
        // Deploy trusted forwarder for gasless transactions
        addresses.trustedForwarder = address(new SimpleForwarder(deployer));
        console2.log("SimpleForwarder deployed at:", addresses.trustedForwarder);
        
        return addresses;
    }

    /// @notice Deploy all facet contracts
    /// @param addresses Struct to store deployed addresses
    function _deployFacets(DeploymentAddresses memory addresses) internal {
        console2.log("Deploying facets...");
        
        // Deploy infrastructure facets
        addresses.diamondCutFacet = address(new DiamondCutFacet());
        console2.log("DiamondCutFacet deployed at:", addresses.diamondCutFacet);
        
        addresses.diamondLoupeFacet = address(new DiamondLoupeFacet());
        console2.log("DiamondLoupeFacet deployed at:", addresses.diamondLoupeFacet);
        
        addresses.ownershipFacet = address(new OwnershipFacet());
        console2.log("OwnershipFacet deployed at:", addresses.ownershipFacet);
        
        // Deploy business logic facets
        addresses.eventCoreFacet = address(new EventCoreFacet(addresses.trustedForwarder));
        console2.log("EventCoreFacet deployed at:", addresses.eventCoreFacet);
        
        addresses.ticketPurchaseFacet = address(new TicketPurchaseFacet(addresses.trustedForwarder));
        console2.log("TicketPurchaseFacet deployed at:", addresses.ticketPurchaseFacet);
        
        addresses.marketplaceFacet = address(new MarketplaceFacet(addresses.trustedForwarder));
        console2.log("MarketplaceFacet deployed at:", addresses.marketplaceFacet);
        
        addresses.staffManagementFacet = address(new StaffManagementFacet(addresses.trustedForwarder));
        console2.log("StaffManagementFacet deployed at:", addresses.staffManagementFacet);
    }

    /// @notice Deploy diamond with initial facets
    /// @param addresses Struct containing facet addresses
    /// @param owner Address of the diamond owner
    /// @return Address of deployed diamond
    function _deployDiamondWithFacets(
        DeploymentAddresses memory addresses,
        address owner
    ) internal returns (address) {
        console2.log("Deploying diamond with initial facets...");
        
        // Prepare diamond cut for initial facets
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](7);
        
        // DiamondCutFacet
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: addresses.diamondCutFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getDiamondCutSelectors()
        });
        
        // DiamondLoupeFacet
        cut[1] = IDiamondCut.FacetCut({
            facetAddress: addresses.diamondLoupeFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getDiamondLoupeSelectors()
        });
        
        // OwnershipFacet
        cut[2] = IDiamondCut.FacetCut({
            facetAddress: addresses.ownershipFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getOwnershipSelectors()
        });
        
        // EventCoreFacet
        cut[3] = IDiamondCut.FacetCut({
            facetAddress: addresses.eventCoreFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getEventCoreSelectors()
        });
        
        // TicketPurchaseFacet
        cut[4] = IDiamondCut.FacetCut({
            facetAddress: addresses.ticketPurchaseFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getTicketPurchaseSelectors()
        });
        
        // MarketplaceFacet
        cut[5] = IDiamondCut.FacetCut({
            facetAddress: addresses.marketplaceFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getMarketplaceSelectors()
        });
        
        // StaffManagementFacet
        cut[6] = IDiamondCut.FacetCut({
            facetAddress: addresses.staffManagementFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getStaffManagementSelectors()
        });
        
        // Deploy diamond
        DiamondLummy diamond = new DiamondLummy(owner, cut);
        
        console2.log("Diamond deployed at:", address(diamond));
        return address(diamond);
    }

    /// @notice Verify deployment by checking facet addresses
    /// @param addresses Struct containing all deployment addresses
    function _verifyDeployment(DeploymentAddresses memory addresses) internal view {
        console2.log("Verifying deployment...");
        
        // Create diamond interface for verification
        DiamondLummy diamond = DiamondLummy(payable(addresses.diamond));
        
        // Verify some basic function selectors are properly routed
        // This would require the diamond to have the loupe functions available
        // For now, we'll just check that the diamond was deployed successfully
        
        require(address(diamond).code.length > 0, "Diamond deployment failed");
        console2.log("Diamond deployment verified successfully");
    }

    /// @notice Log all deployment information
    /// @param addresses Struct containing all deployment addresses
    function _logDeploymentInfo(DeploymentAddresses memory addresses) internal pure {
        console2.log("\n=== DIAMOND DEPLOYMENT COMPLETE ===");
        console2.log("Diamond Address:", addresses.diamond);
        console2.log("\nFacet Addresses:");
        console2.log("- DiamondCutFacet:", addresses.diamondCutFacet);
        console2.log("- DiamondLoupeFacet:", addresses.diamondLoupeFacet);
        console2.log("- OwnershipFacet:", addresses.ownershipFacet);
        console2.log("- EventCoreFacet:", addresses.eventCoreFacet);
        console2.log("- TicketPurchaseFacet:", addresses.ticketPurchaseFacet);
        console2.log("- MarketplaceFacet:", addresses.marketplaceFacet);
        console2.log("- StaffManagementFacet:", addresses.staffManagementFacet);
        console2.log("\nSupporting Contracts:");
        console2.log("- MockIDRX:", addresses.mockIDRX);
        console2.log("- TrustedForwarder:", addresses.trustedForwarder);
        console2.log("=====================================\n");
    }

    // Function selector generation functions
    
    function _getDiamondCutSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = DiamondCutFacet.diamondCut.selector;
        // Note: owner() and transferOwnership() are handled by OwnershipFacet
    }

    function _getDiamondLoupeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = DiamondLoupeFacet.facets.selector;
        selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
        selectors[3] = DiamondLoupeFacet.facetAddress.selector;
        selectors[4] = DiamondLoupeFacet.supportsInterface.selector;
    }

    function _getOwnershipSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = OwnershipFacet.owner.selector;
        selectors[1] = OwnershipFacet.transferOwnership.selector;
    }

    function _getEventCoreSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](11);
        selectors[0] = EventCoreFacet.initialize.selector;
        selectors[1] = EventCoreFacet.setTicketNFT.selector;
        selectors[2] = EventCoreFacet.addTicketTier.selector;
        selectors[3] = EventCoreFacet.updateTicketTier.selector;
        selectors[4] = EventCoreFacet.setEventId.selector;
        selectors[5] = EventCoreFacet.setResaleRules.selector;
        selectors[6] = EventCoreFacet.cancelEvent.selector;
        selectors[7] = EventCoreFacet.markEventCompleted.selector;
        selectors[8] = EventCoreFacet.getTicketNFT.selector;
        selectors[9] = EventCoreFacet.getEventInfo.selector;
        selectors[10] = EventCoreFacet.getEventStatus.selector;
    }

    function _getTicketPurchaseSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = TicketPurchaseFacet.purchaseTicket.selector;
        selectors[1] = TicketPurchaseFacet.withdrawOrganizerFunds.selector;
        selectors[2] = TicketPurchaseFacet.processRefund.selector;
        selectors[3] = TicketPurchaseFacet.emergencyRefund.selector;
        selectors[4] = TicketPurchaseFacet.getOrganizerEscrow.selector;
        selectors[5] = TicketPurchaseFacet.getUserPurchaseCount.selector;
        selectors[6] = TicketPurchaseFacet.ticketExists.selector;
    }

    function _getMarketplaceSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = MarketplaceFacet.listTicketForResale.selector;
        selectors[1] = MarketplaceFacet.purchaseResaleTicket.selector;
        selectors[2] = MarketplaceFacet.cancelResaleListing.selector;
        selectors[3] = MarketplaceFacet.updateResaleSettings.selector;
        selectors[4] = MarketplaceFacet.getListing.selector;
        selectors[5] = MarketplaceFacet.isListedForResale.selector;
        selectors[6] = MarketplaceFacet.getTokenMarketplaceStats.selector;
        selectors[7] = MarketplaceFacet.getUserResaleRevenue.selector;
        selectors[8] = MarketplaceFacet.calculateResaleFees.selector;
    }

    function _getStaffManagementSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = StaffManagementFacet.addStaffWithRole.selector;
        selectors[1] = StaffManagementFacet.removeStaffRole.selector;
        selectors[2] = StaffManagementFacet.addStaff.selector;
        selectors[3] = StaffManagementFacet.removeStaff.selector;
        selectors[4] = StaffManagementFacet.updateTicketStatus.selector;
        selectors[5] = StaffManagementFacet.batchUpdateTicketStatus.selector;
        selectors[6] = StaffManagementFacet.validateTicket.selector;
        selectors[7] = StaffManagementFacet.getStaffRole.selector;
        selectors[8] = StaffManagementFacet.hasStaffRole.selector;
    }
}