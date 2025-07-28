// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {LibDiamond} from "src/diamond/LibDiamond.sol";

/// @title OwnershipFacet - Facet for diamond ownership management
/// @author Lummy Protocol Team
/// @notice Handles ownership operations for the diamond
/// @dev Provides ownership functionality separate from diamond cut operations
contract OwnershipFacet {
    /// @notice Gets the current owner of the diamond
    /// @return owner_ Address of the current owner
    function owner() external view returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }

    /// @notice Transfers ownership of the diamond to a new address
    /// @param _newOwner Address of the new owner
    /// @dev Only current owner can transfer ownership
    /// @custom:security Restricted to current owner only
    function transferOwnership(address _newOwner) external {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setContractOwner(_newOwner);
    }

    /// @notice Emitted when ownership is transferred
    /// @param previousOwner Address of the previous owner
    /// @param newOwner Address of the new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}