// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {LibDiamond} from "src/diamond/LibDiamond.sol";
import {IDiamondLoupe} from "src/diamond/interfaces/IDiamondLoupe.sol";
import {IERC165} from "@openzeppelin/utils/introspection/IERC165.sol";

/// @title DiamondLoupeFacet - Facet for diamond inspection
/// @author Lummy Protocol Team
/// @notice Provides functions to inspect facets and functions in the diamond
/// @dev Implements IDiamondLoupe interface required by EIP-2535
contract DiamondLoupeFacet is IDiamondLoupe, IERC165 {
    /// @notice Gets all facets and their selectors
    /// @return facets_ Array of facet structs
    function facets() external view override returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 numFacets = ds.facetAddresses.length;
        facets_ = new Facet[](numFacets);
        
        for (uint256 i; i < numFacets; ) {
            address facetAddress_ = ds.facetAddresses[i];
            facets_[i].facetAddress = facetAddress_;
            facets_[i].functionSelectors = ds.facetFunctionSelectors[facetAddress_].functionSelectors;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Gets function selectors for a specific facet
    /// @param _facet Address of the facet to query
    /// @return facetFunctionSelectors_ Array of function selectors
    function facetFunctionSelectors(address _facet)
        external
        view
        override
        returns (bytes4[] memory facetFunctionSelectors_)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        facetFunctionSelectors_ = ds.facetFunctionSelectors[_facet].functionSelectors;
    }

    /// @notice Gets all facet addresses
    /// @return facetAddresses_ Array of facet addresses
    function facetAddresses() external view override returns (address[] memory facetAddresses_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        facetAddresses_ = ds.facetAddresses;
    }

    /// @notice Gets the facet address for a function selector
    /// @param _functionSelector Function selector to query
    /// @return facetAddress_ Address of implementing facet
    function facetAddress(bytes4 _functionSelector) external view override returns (address facetAddress_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        facetAddress_ = ds.selectorToFacetAndPosition[_functionSelector].facetAddress;
    }

    /// @notice Checks if contract supports an interface
    /// @param _interfaceId Interface ID to check
    /// @return True if interface is supported
    function supportsInterface(bytes4 _interfaceId) external view override returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.supportedInterfaces[_interfaceId];
    }

    /// @notice Sets interface support status
    /// @param _interfaceId Interface ID to set
    /// @param _supported Whether interface is supported
    /// @dev Only diamond owner can modify interface support
    function setSupportsInterface(bytes4 _interfaceId, bool _supported) external {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[_interfaceId] = _supported;
    }
}