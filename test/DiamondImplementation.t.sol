// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test, console2} from "forge-std/Test.sol";
import {DiamondLummy} from "src/diamond/DiamondLummy.sol";
import {DiamondCutFacet} from "src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "src/diamond/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "src/diamond/facets/OwnershipFacet.sol";
import {EventCoreFacet} from "src/diamond/facets/EventCoreFacet.sol";
import {TicketPurchaseFacet} from "src/diamond/facets/TicketPurchaseFacet.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "src/diamond/interfaces/IDiamondLoupe.sol";
import {MockIDRX} from "src/core/MockIDRX.sol";
import {SimpleForwarder} from "src/core/SimpleForwarder.sol";

contract DiamondImplementationTest is Test {
    DiamondLummy diamond;
    DiamondCutFacet diamondCutFacet;
    DiamondLoupeFacet diamondLoupeFacet;
    OwnershipFacet ownershipFacet;
    EventCoreFacet eventCoreFacet;
    TicketPurchaseFacet ticketPurchaseFacet;
    MockIDRX mockIDRX;
    SimpleForwarder forwarder;
    
    address owner = address(0x1);
    address organizer = address(0x2);
    address user = address(0x3);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy supporting contracts
        mockIDRX = new MockIDRX();
        forwarder = new SimpleForwarder(owner);
        
        // Deploy facets
        diamondCutFacet = new DiamondCutFacet();
        diamondLoupeFacet = new DiamondLoupeFacet();
        ownershipFacet = new OwnershipFacet();
        eventCoreFacet = new EventCoreFacet(address(forwarder));
        ticketPurchaseFacet = new TicketPurchaseFacet(address(forwarder));
        
        // Prepare diamond cut for basic facets
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](5);
        
        // DiamondCutFacet
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(diamondCutFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getDiamondCutSelectors()
        });
        
        // DiamondLoupeFacet
        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getDiamondLoupeSelectors()
        });
        
        // OwnershipFacet
        cut[2] = IDiamondCut.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getOwnershipSelectors()
        });
        
        // EventCoreFacet
        cut[3] = IDiamondCut.FacetCut({
            facetAddress: address(eventCoreFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getEventCoreSelectors()
        });
        
        // TicketPurchaseFacet
        cut[4] = IDiamondCut.FacetCut({
            facetAddress: address(ticketPurchaseFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getTicketPurchaseSelectors()
        });
        
        // Deploy diamond
        diamond = new DiamondLummy(owner, cut);
        
        vm.stopPrank();
    }
    
    function testDiamondDeployment() public {
        // Test that diamond was deployed successfully
        assertTrue(address(diamond).code.length > 0);
        console2.log("Diamond deployed at:", address(diamond));
        console2.log("Diamond bytecode size:", address(diamond).code.length);
        
        // Verify it's well under the EIP-170 limit
        assertLt(address(diamond).code.length, 24576, "Diamond exceeds EIP-170 limit");
    }
    
    function testOwnershipFunctionality() public {
        // Test owner() function through diamond
        address diamondOwner = OwnershipFacet(address(diamond)).owner();
        assertEq(diamondOwner, owner, "Diamond owner should be set correctly");
        
        console2.log("Diamond owner verified:", diamondOwner);
    }
    
    function testDiamondLoupeFunctionality() public {
        // Test facets() function through diamond
        IDiamondLoupe.Facet[] memory facets = DiamondLoupeFacet(address(diamond)).facets();
        
        assertGt(facets.length, 0, "Should have facets");
        console2.log("Number of facets:", facets.length);
        
        // Test facetAddresses() function
        address[] memory facetAddresses = DiamondLoupeFacet(address(diamond)).facetAddresses();
        assertEq(facetAddresses.length, facets.length, "Facet addresses should match facets count");
        
        for (uint i = 0; i < facetAddresses.length; i++) {
            console2.log("Facet", i, "address:", facetAddresses[i]);
        }
    }
    
    function testEventCoreFunctionality() public {
        vm.startPrank(owner);
        
        // Test getEventInfo through diamond - should return empty initially
        (string memory name, string memory description, uint256 date, string memory venue, address orgAddr) = 
            EventCoreFacet(address(diamond)).getEventInfo();
        
        // Initially should be empty
        assertEq(bytes(name).length, 0, "Name should be empty initially");
        
        console2.log("Event info retrieved successfully");
        
        vm.stopPrank();
    }
    
    function testFacetFunctionRouting() public {
        // Test that function selectors route to correct facets
        bytes4 ownerSelector = OwnershipFacet.owner.selector;
        address facetAddr = DiamondLoupeFacet(address(diamond)).facetAddress(ownerSelector);
        
        assertEq(facetAddr, address(ownershipFacet), "owner() should route to OwnershipFacet");
        
        bytes4 facetsSelector = DiamondLoupeFacet.facets.selector;
        facetAddr = DiamondLoupeFacet(address(diamond)).facetAddress(facetsSelector);
        
        assertEq(facetAddr, address(diamondLoupeFacet), "facets() should route to DiamondLoupeFacet");
        
        console2.log("Function selector routing verified");
    }
    
    function testContractSizes() public {
        console2.log("\n=== CONTRACT SIZE VERIFICATION ===");
        console2.log("DiamondLummy size:", address(diamond).code.length, "bytes");
        console2.log("DiamondCutFacet size:", address(diamondCutFacet).code.length, "bytes");
        console2.log("DiamondLoupeFacet size:", address(diamondLoupeFacet).code.length, "bytes");
        console2.log("OwnershipFacet size:", address(ownershipFacet).code.length, "bytes");
        console2.log("EventCoreFacet size:", address(eventCoreFacet).code.length, "bytes");
        console2.log("TicketPurchaseFacet size:", address(ticketPurchaseFacet).code.length, "bytes");
        
        // Verify all are under EIP-170 limit
        assertLt(address(diamond).code.length, 24576, "Diamond exceeds limit");
        assertLt(address(diamondCutFacet).code.length, 24576, "DiamondCutFacet exceeds limit");
        assertLt(address(diamondLoupeFacet).code.length, 24576, "DiamondLoupeFacet exceeds limit");
        assertLt(address(ownershipFacet).code.length, 24576, "OwnershipFacet exceeds limit");
        assertLt(address(eventCoreFacet).code.length, 24576, "EventCoreFacet exceeds limit");
        assertLt(address(ticketPurchaseFacet).code.length, 24576, "TicketPurchaseFacet exceeds limit");
        
        console2.log("All contracts are under EIP-170 limit (24,576 bytes)");
    }
    
    // Helper functions for function selectors
    function _getDiamondCutSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = DiamondCutFacet.diamondCut.selector;
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
        selectors = new bytes4[](5);
        selectors[0] = EventCoreFacet.initialize.selector;
        selectors[1] = EventCoreFacet.addTicketTier.selector;
        selectors[2] = EventCoreFacet.cancelEvent.selector;
        selectors[3] = EventCoreFacet.getEventInfo.selector;
        selectors[4] = EventCoreFacet.getEventStatus.selector;
    }
    
    function _getTicketPurchaseSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = TicketPurchaseFacet.purchaseTicket.selector;
        selectors[1] = TicketPurchaseFacet.emergencyRefund.selector;
        selectors[2] = TicketPurchaseFacet.getOrganizerEscrow.selector;
    }
}