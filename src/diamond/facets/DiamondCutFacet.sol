// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {LibDiamond} from "src/diamond/LibDiamond.sol";

/// @title DiamondCutFacet - Facet for managing diamond cuts
/// @author Lummy Protocol Team
/// @notice Handles adding, replacing, and removing facets from the diamond
/// @dev Implements IDiamondCut interface for EIP-2535 compliance
contract DiamondCutFacet is IDiamondCut {
    /// @notice Performs diamond cut operations to modify facets
    /// @param _diamondCut Array of facet cuts to perform
    /// @param _init Address of initialization contract
    /// @param _calldataParam Initialization function call data
    /// @dev Only diamond owner can perform diamond cuts
    /// @custom:security Restricted to diamond owner to prevent unauthorized modifications
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldataParam
    ) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldataParam);
    }

    // Note: owner() and transferOwnership() are handled by OwnershipFacet
    // to avoid function selector collisions
}