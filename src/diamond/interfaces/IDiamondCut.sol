// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IDiamondCut - Interface for diamond cut functionality
/// @author Lummy Protocol Team  
/// @notice Interface for adding, replacing, and removing facets from a diamond
/// @dev Based on EIP-2535 Diamond standard
interface IDiamondCut {
    /// @notice Enumeration of facet cut actions
    enum FacetCutAction {
        Add,        // Add new functions to diamond
        Replace,    // Replace existing functions with new implementation
        Remove      // Remove functions from diamond
    }

    /// @notice Struct defining a facet cut operation
    struct FacetCut {
        address facetAddress;           // Address of the facet contract
        FacetCutAction action;          // Action to perform (Add/Replace/Remove)
        bytes4[] functionSelectors;     // Array of function selectors to cut
    }

    /// @notice Performs a diamond cut operation
    /// @param diamondCut Array of facet cuts to perform
    /// @param init Address of initialization contract (can be zero)
    /// @param calldataParam Initialization function call data
    /// @dev Emits DiamondCut event for each operation performed
    function diamondCut(
        FacetCut[] calldata diamondCut,
        address init,
        bytes calldata calldataParam
    ) external;

    /// @notice Emitted when diamond cut is performed
    event DiamondCut(FacetCut[] diamondCut, address init, bytes calldataParam);
}