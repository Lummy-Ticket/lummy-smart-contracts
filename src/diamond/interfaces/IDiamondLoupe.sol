// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IDiamondLoupe - Interface for diamond inspection functionality
/// @author Lummy Protocol Team
/// @notice Interface for inspecting facets and functions in a diamond
/// @dev Based on EIP-2535 Diamond standard - required for compliance
interface IDiamondLoupe {
    /// @notice Struct representing a facet and its selectors
    struct Facet {
        address facetAddress;           // Address of the facet contract
        bytes4[] functionSelectors;     // Array of function selectors in this facet
    }

    /// @notice Gets all facets and their selectors
    /// @return facets_ Array of facet structs containing addresses and selectors
    function facets() external view returns (Facet[] memory facets_);

    /// @notice Gets all function selectors supported by a specific facet
    /// @param facet Address of the facet to query
    /// @return facetFunctionSelectors_ Array of function selectors for the facet
    function facetFunctionSelectors(address facet)
        external
        view
        returns (bytes4[] memory facetFunctionSelectors_);

    /// @notice Gets all facet addresses used by the diamond
    /// @return facetAddresses_ Array of facet addresses
    function facetAddresses() external view returns (address[] memory facetAddresses_);

    /// @notice Gets the facet address that supports the given selector
    /// @param functionSelector Function selector to query
    /// @return facetAddress_ Address of the facet that implements the function
    function facetAddress(bytes4 functionSelector) external view returns (address facetAddress_);
}