// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";

/// @title LibDiamond - Core diamond functionality library
/// @author Lummy Protocol Team
/// @notice Implements EIP-2535 Diamond standard for Lummy protocol
/// @dev Based on Nick Mudge's reference implementation with Lummy-specific optimizations
library LibDiamond {
    /// @notice Diamond storage position in contract storage
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    /// @notice Struct to hold diamond-specific state variables
    struct DiamondStorage {
        /// @dev Maps function selectors to facet addresses and function selector positions
        mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
        /// @dev Maps facet addresses to function selectors
        mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
        /// @dev Array of facet addresses
        address[] facetAddresses;
        /// @dev Maps supported interfaces to implementation status
        mapping(bytes4 => bool) supportedInterfaces;
        /// @dev Contract owner for access control
        address contractOwner;
    }

    /// @notice Struct to store facet address and position information
    struct FacetAddressAndPosition {
        /// @dev Address of the facet contract
        address facetAddress;
        /// @dev Position in facetFunctionSelectors.functionSelectors array
        uint96 functionSelectorPosition;
    }

    /// @notice Struct to store facet function selectors
    struct FacetFunctionSelectors {
        /// @dev Array of function selectors for this facet
        bytes4[] functionSelectors;
        /// @dev Position of facet address in facetAddresses array
        uint256 facetAddressPosition;
    }

    /// @notice Emitted when diamond is cut (facets added/replaced/removed)
    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

    /// @notice Custom errors for gas efficiency
    error NoSelectorsGivenToAdd();
    error NotContractOwner(address user, address contractOwner);
    error NoSelectorsProvidedForFacetForCut(address facetAddress);
    error CannotAddSelectorsToZeroAddress(bytes4[] selectors);
    error NoBytecodeAtAddress(address facetAddress, string message);
    error IncorrectFacetCutAction(uint8 action);
    error CannotAddFunctionToDiamondThatAlreadyExists(bytes4 selector);
    error CannotReplaceFunctionsFromFacetWithZeroAddress(bytes4[] selectors);
    error CannotReplaceImmutableFunction(bytes4 selector);
    error CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet(bytes4 selector);
    error CannotReplaceFunctionThatDoesNotExists(bytes4 selector);
    error RemoveFacetAddressMustBeZeroAddress(address facetAddress);
    error CannotRemoveFunctionThatDoesNotExist(bytes4 selector);
    error CannotRemoveImmutableFunction(bytes4 selector);
    error InitializationFunctionReverted(address initializationContractAddress, bytes calldataParam);

    /// @notice Gets the diamond storage struct
    /// @return ds The diamond storage struct
    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    /// @notice Emits DiamondCut event for tracking facet changes
    /// @param diamondCut Array of facet cuts being performed
    /// @param init Address of initialization contract (can be zero)
    /// @param calldataParam Initialization function call data
    function emitDiamondCutEvent(
        IDiamondCut.FacetCut[] memory diamondCut,
        address init,
        bytes memory calldataParam
    ) internal {
        emit DiamondCut(diamondCut, init, calldataParam);
    }

    /// @notice Sets the contract owner for access control
    /// @param newOwner Address of the new owner
    function setContractOwner(address newOwner) internal {
        DiamondStorage storage ds = diamondStorage();
        address previousOwner = ds.contractOwner;
        ds.contractOwner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /// @notice Gets the current contract owner
    /// @return contractOwner_ The current owner address
    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = diamondStorage().contractOwner;
    }

    /// @notice Enforces that the caller is the contract owner
    function enforceIsContractOwner() internal view {
        if (msg.sender != diamondStorage().contractOwner) {
            revert NotContractOwner(msg.sender, diamondStorage().contractOwner);
        }
    }

    /// @notice Performs diamond cut operations (add/replace/remove facets)
    /// @param diamondCut Array of facet cuts to perform
    /// @param init Address of initialization contract
    /// @param calldataParam Initialization call data
    function diamondCut(
        IDiamondCut.FacetCut[] memory diamondCut,
        address init,
        bytes memory calldataParam
    ) internal {
        for (uint256 facetIndex; facetIndex < diamondCut.length; ) {
            IDiamondCut.FacetCutAction action = diamondCut[facetIndex].action;
            if (action == IDiamondCut.FacetCutAction.Add) {
                addFunctions(diamondCut[facetIndex].facetAddress, diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Replace) {
                replaceFunctions(diamondCut[facetIndex].facetAddress, diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Remove) {
                removeFunctions(diamondCut[facetIndex].facetAddress, diamondCut[facetIndex].functionSelectors);
            } else {
                revert IncorrectFacetCutAction(uint8(action));
            }
            unchecked {
                ++facetIndex;
            }
        }
        emitDiamondCutEvent(diamondCut, init, calldataParam);
        initializeDiamondCut(init, calldataParam);
    }

    /// @notice Adds new functions to the diamond
    /// @param facetAddress Address of the facet contract
    /// @param functionSelectors Array of function selectors to add
    function addFunctions(address facetAddress, bytes4[] memory functionSelectors) internal {
        if (functionSelectors.length == 0) {
            revert NoSelectorsGivenToAdd();
        }
        DiamondStorage storage ds = diamondStorage();
        if (facetAddress == address(0)) {
            revert CannotAddSelectorsToZeroAddress(functionSelectors);
        }
        uint96 selectorPosition = uint96(ds.facetFunctionSelectors[facetAddress].functionSelectors.length);
        // add new facet address if it does not exist
        if (selectorPosition == 0) {
            addFacet(ds, facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < functionSelectors.length; ) {
            bytes4 selector = functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacetAddress != address(0)) {
                revert CannotAddFunctionToDiamondThatAlreadyExists(selector);
            }
            addFunction(ds, selector, selectorPosition, facetAddress);
            unchecked {
                ++selectorPosition;
                ++selectorIndex;
            }
        }
    }

    /// @notice Replaces existing functions in the diamond
    /// @param facetAddress Address of the new facet contract
    /// @param functionSelectors Array of function selectors to replace
    function replaceFunctions(address facetAddress, bytes4[] memory functionSelectors) internal {
        if (functionSelectors.length == 0) {
            revert NoSelectorsProvidedForFacetForCut(facetAddress);
        }
        DiamondStorage storage ds = diamondStorage();
        if (facetAddress == address(0)) {
            revert CannotReplaceFunctionsFromFacetWithZeroAddress(functionSelectors);
        }
        uint96 selectorPosition = uint96(ds.facetFunctionSelectors[facetAddress].functionSelectors.length);
        // add new facet address if it does not exist
        if (selectorPosition == 0) {
            addFacet(ds, facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < functionSelectors.length; ) {
            bytes4 selector = functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacetAddress == facetAddress) {
                revert CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet(selector);
            }
            if (oldFacetAddress == address(0)) {
                revert CannotReplaceFunctionThatDoesNotExists(selector);
            }
            // replace old facet address
            removeFunction(ds, oldFacetAddress, selector);
            addFunction(ds, selector, selectorPosition, facetAddress);
            unchecked {
                ++selectorPosition;
                ++selectorIndex;
            }
        }
    }

    /// @notice Removes functions from the diamond
    /// @param facetAddress Must be zero address for remove action
    /// @param functionSelectors Array of function selectors to remove
    function removeFunctions(address facetAddress, bytes4[] memory functionSelectors) internal {
        if (functionSelectors.length == 0) {
            revert NoSelectorsProvidedForFacetForCut(facetAddress);
        }
        DiamondStorage storage ds = diamondStorage();
        if (facetAddress != address(0)) {
            revert RemoveFacetAddressMustBeZeroAddress(facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < functionSelectors.length; ) {
            bytes4 selector = functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacetAddress == address(0)) {
                revert CannotRemoveFunctionThatDoesNotExist(selector);
            }
            removeFunction(ds, oldFacetAddress, selector);
            unchecked {
                ++selectorIndex;
            }
        }
    }

    /// @notice Adds a new facet to the diamond
    /// @param ds Diamond storage reference
    /// @param facetAddress Address of the facet to add
    function addFacet(DiamondStorage storage ds, address facetAddress) internal {
        enforceHasContractCode(facetAddress, "LibDiamondCut: New facet has no code");
        ds.facetFunctionSelectors[facetAddress].facetAddressPosition = ds.facetAddresses.length;
        ds.facetAddresses.push(facetAddress);
    }

    /// @notice Adds a function to a facet
    /// @param ds Diamond storage reference
    /// @param selector Function selector to add
    /// @param selectorPosition Position in selector array
    /// @param facetAddress Address of the facet
    function addFunction(
        DiamondStorage storage ds,
        bytes4 selector,
        uint96 selectorPosition,
        address facetAddress
    ) internal {
        ds.selectorToFacetAndPosition[selector].functionSelectorPosition = selectorPosition;
        ds.facetFunctionSelectors[facetAddress].functionSelectors.push(selector);
        ds.selectorToFacetAndPosition[selector].facetAddress = facetAddress;
    }

    /// @notice Removes a function from a facet
    /// @param ds Diamond storage reference
    /// @param facetAddress Address of the facet
    /// @param selector Function selector to remove
    function removeFunction(DiamondStorage storage ds, address facetAddress, bytes4 selector) internal {
        // an immutable function is a function defined directly in a diamond
        if (facetAddress == address(this)) {
            revert CannotRemoveImmutableFunction(selector);
        }
        // replace selector with last selector, then delete last selector
        uint256 selectorPosition = ds.selectorToFacetAndPosition[selector].functionSelectorPosition;
        uint256 lastSelectorPosition = ds.facetFunctionSelectors[facetAddress].functionSelectors.length - 1;
        // if not the same then replace selector with lastSelector
        if (selectorPosition != lastSelectorPosition) {
            bytes4 lastSelector = ds.facetFunctionSelectors[facetAddress].functionSelectors[lastSelectorPosition];
            ds.facetFunctionSelectors[facetAddress].functionSelectors[selectorPosition] = lastSelector;
            ds.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint96(selectorPosition);
        }
        // delete the last selector
        ds.facetFunctionSelectors[facetAddress].functionSelectors.pop();
        delete ds.selectorToFacetAndPosition[selector];

        // if no more selectors for facet address then delete the facet address
        if (lastSelectorPosition == 0) {
            // replace facet address with last facet address and delete last facet address
            uint256 lastFacetAddressPosition = ds.facetAddresses.length - 1;
            uint256 facetAddressPosition = ds.facetFunctionSelectors[facetAddress].facetAddressPosition;
            if (facetAddressPosition != lastFacetAddressPosition) {
                address lastFacetAddress = ds.facetAddresses[lastFacetAddressPosition];
                ds.facetAddresses[facetAddressPosition] = lastFacetAddress;
                ds.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = facetAddressPosition;
            }
            ds.facetAddresses.pop();
            delete ds.facetFunctionSelectors[facetAddress].facetAddressPosition;
        }
    }

    /// @notice Initializes diamond cut with initialization function call
    /// @param init Address of initialization contract
    /// @param calldataParam Initialization call data
    function initializeDiamondCut(address init, bytes memory calldataParam) internal {
        if (init == address(0)) {
            return;
        }
        enforceHasContractCode(init, "LibDiamondCut: _init address has no code");
        (bool success, bytes memory error) = init.delegatecall(calldataParam);
        if (!success) {
            if (error.length > 0) {
                assembly {
                    let returndata_size := mload(error)
                    revert(add(32, error), returndata_size)
                }
            } else {
                revert InitializationFunctionReverted(init, calldataParam);
            }
        }
    }

    /// @notice Enforces that an address has contract code
    /// @param contractAddress Address to check
    /// @param errorMessage Error message if no code found
    function enforceHasContractCode(address contractAddress, string memory errorMessage) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(contractAddress)
        }
        if (contractSize == 0) {
            revert NoBytecodeAtAddress(contractAddress, errorMessage);
        }
    }

    /// @notice Emitted when ownership is transferred
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}