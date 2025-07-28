// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {LibDiamond} from "src/diamond/LibDiamond.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {LibAppStorage} from "src/diamond/LibAppStorage.sol";

/// @title DiamondLummy - Main diamond contract for Lummy protocol
/// @author Lummy Protocol Team
/// @notice Main diamond contract implementing EIP-2535 for Lummy ticketing system
/// @dev Uses Diamond pattern to overcome EIP-170 contract size limits while maintaining single address UX
/// @custom:version 2.0.0 Diamond Implementation
/// @custom:security-contact security@lummy.io
contract DiamondLummy {
    /// @notice Initializes the diamond with owner and basic facets
    /// @param owner Address of the diamond owner (typically the factory)
    /// @param diamondCut Initial facets to add during deployment
    constructor(address owner, IDiamondCut.FacetCut[] memory diamondCut) payable {
        // Set contract owner in diamond storage
        LibDiamond.setContractOwner(owner);

        // Initialize basic app storage
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        s.factory = msg.sender; // Factory deploys the diamond

        // Add initial facets via diamond cut
        LibDiamond.diamondCut(diamondCut, address(0), "");
    }

    /// @notice Fallback function that delegates calls to appropriate facets
    /// @dev Uses delegatecall to maintain diamond storage context
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        
        // Get diamond storage
        assembly {
            ds.slot := position
        }
        
        // Get facet address for function selector
        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
        
        require(facet != address(0), "DiamondLummy: Function does not exist");
        
        // Execute external function from facet using delegatecall and return any value
        assembly {
            // Copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            
            // Execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            
            // Get any return value
            returndatacopy(0, 0, returndatasize())
            
            // Return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /// @notice Allows the contract to receive Ether
    /// @dev Required for receiving payments and refunds
    receive() external payable {}
}