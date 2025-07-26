// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {ECDSA} from "@openzeppelin/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/utils/Nonces.sol";

/**
 * @title SimpleForwarder
 * @author Lummy Protocol Team
 * @notice Trusted forwarder contract for gasless transactions using ERC-2771 standard
 * @dev Implements EIP-712 for signature verification and comprehensive gas management.
 *      Allows designated paymaster to execute transactions on behalf of users.
 * @custom:version 2.0.0
 * @custom:security-contact security@lummy.io
 * @custom:standard ERC-2771, EIP-712
 */
contract SimpleForwarder is EIP712, Nonces {
    using ECDSA for bytes32;

    /* ========== STRUCTS ========== */
    
    /**
     * @notice Structure for forward request data
     * @param from Address of the user making the request
     * @param to Target contract address
     * @param value ETH value to send with the transaction
     * @param gas Gas limit for the forwarded transaction
     * @param nonce User's nonce to prevent replay attacks
     * @param data Encoded function call data
     */
    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
    }

    /* ========== CONSTANTS ========== */
    
    /// @dev EIP-712 type hash for ForwardRequest struct
    bytes32 private constant _FORWARD_REQUEST_TYPEHASH =
        keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)");

    /* ========== STATE VARIABLES ========== */
    
    /// @notice Address authorized to pay for gas fees
    address public paymaster;
    
    /// @dev Maps addresses that can call execute function
    mapping(address => bool) public authorizedCallers;
    
    /* ========== GAS MANAGEMENT ========== */
    
    /// @notice Contract that manages gas limits (e.g., EventFactory)
    address public gasManager;
    
    /// @notice Default maximum gas limit if no gas manager is set
    uint256 public defaultMaxGas = 500000;
    
    /// @notice Whether gas validation is enabled
    bool public gasValidationEnabled = true;
    
    /* ========== EVENTS ========== */
    
    /// @notice Emitted when a transaction is forwarded
    event ForwardedTransaction(address indexed from, address indexed to, bool success, bytes returndata);
    
    /// @notice Emitted when paymaster is updated
    event PaymasterUpdated(address indexed oldPaymaster, address indexed newPaymaster);
    
    /// @notice Emitted when authorized caller is added
    event AuthorizedCallerAdded(address indexed caller);
    
    /// @notice Emitted when authorized caller is removed
    event AuthorizedCallerRemoved(address indexed caller);
    
    /// @notice Emitted when gas manager is updated
    event GasManagerUpdated(address indexed gasManager);
    
    /// @notice Emitted when default max gas is updated
    event DefaultMaxGasUpdated(uint256 newMaxGas);
    
    /// @notice Emitted when gas validation is toggled
    event GasValidationToggled(bool enabled);

    /* ========== MODIFIERS ========== */
    
    /**
     * @dev Restricts function access to paymaster only
     */
    modifier onlyPaymaster() {
        require(msg.sender == paymaster, "SimpleForwarder: not paymaster");
        _;
    }

    /**
     * @dev Restricts function access to authorized callers or paymaster
     */
    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender] || msg.sender == paymaster, "SimpleForwarder: not authorized");
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    
    /**
     * @notice Initializes the SimpleForwarder with paymaster address
     * @dev Sets up EIP-712 domain separator and authorizes paymaster
     * @param _paymaster Address that will pay for gas fees
     */
    constructor(address _paymaster) EIP712("SimpleForwarder", "1") {
        paymaster = _paymaster;
        authorizedCallers[_paymaster] = true;
    }
    
    /* ========== GAS MANAGEMENT ========== */
    
    /**
     * @notice Sets the gas manager contract for advanced gas validation
     * @dev Gas manager provides function-specific gas limits (e.g., EventFactory)
     * @param _gasManager Address of the gas manager contract
     * @custom:security Only paymaster can call
     */
    function setGasManager(address _gasManager) external onlyPaymaster {
        gasManager = _gasManager;
        emit GasManagerUpdated(_gasManager);
    }
    
    /**
     * @notice Sets the default maximum gas limit for transactions
     * @dev Must be between 21000 (basic transaction) and 1M gas
     * @param _maxGas New default maximum gas limit
     * @custom:security Only paymaster can call, validates gas boundaries
     */
    function setDefaultMaxGas(uint256 _maxGas) external onlyPaymaster {
        require(_maxGas > 21000, "Gas too low"); // Minimum for basic transaction
        require(_maxGas <= 1000000, "Gas too high"); // Maximum 1M gas
        defaultMaxGas = _maxGas;
        emit DefaultMaxGasUpdated(_maxGas);
    }
    
    /**
     * @notice Enables or disables gas validation for transactions
     * @dev When disabled, gas limits are not enforced
     * @param _enabled True to enable validation, false to disable
     * @custom:security Only paymaster can call
     */
    function toggleGasValidation(bool _enabled) external onlyPaymaster {
        gasValidationEnabled = _enabled;
        emit GasValidationToggled(_enabled);
    }

    /* ========== PAYMASTER MANAGEMENT ========== */
    
    /**
     * @notice Updates the paymaster address
     * @dev Only current paymaster can transfer paymaster role.
     *      Automatically updates authorized caller mapping.
     * @param newPaymaster Address of the new paymaster
     * @custom:security Only current paymaster can call, validates address
     * @custom:authorization Automatically updates authorized caller status
     */
    function setPaymaster(address newPaymaster) external onlyPaymaster {
        require(newPaymaster != address(0), "SimpleForwarder: invalid paymaster");
        address oldPaymaster = paymaster;
        paymaster = newPaymaster;
        
        // Update authorized callers mapping
        authorizedCallers[oldPaymaster] = false;
        authorizedCallers[newPaymaster] = true;
        
        emit PaymasterUpdated(oldPaymaster, newPaymaster);
    }

    /**
     * @notice Adds an address to the authorized callers list
     * @dev Authorized callers can execute forwarded transactions
     * @param caller Address to authorize
     * @custom:security Only paymaster can call, validates address
     */
    function addAuthorizedCaller(address caller) external onlyPaymaster {
        require(caller != address(0), "SimpleForwarder: invalid caller");
        authorizedCallers[caller] = true;
        emit AuthorizedCallerAdded(caller);
    }

    /**
     * @notice Removes an address from the authorized callers list
     * @dev Cannot remove the paymaster from authorized callers
     * @param caller Address to remove authorization from
     * @custom:security Only paymaster can call, prevents removing paymaster
     */
    function removeAuthorizedCaller(address caller) external onlyPaymaster {
        require(caller != paymaster, "SimpleForwarder: cannot remove paymaster");
        authorizedCallers[caller] = false;
        emit AuthorizedCallerRemoved(caller);
    }

    /* ========== SIGNATURE VERIFICATION ========== */
    
    /**
     * @notice Verifies the signature of a ForwardRequest
     * @dev Uses EIP-712 typed data hashing and ECDSA signature recovery.
     *      Validates both signature authenticity and nonce freshness.
     * @param req ForwardRequest struct containing transaction data
     * @param signature User's signature over the typed data hash
     * @return bool True if signature is valid and nonce matches
     * @custom:security Prevents replay attacks through nonce validation
     * @custom:standard EIP-712 compliant signature verification
     */
    function verify(ForwardRequest calldata req, bytes calldata signature) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(_FORWARD_REQUEST_TYPEHASH, req.from, req.to, req.value, req.gas, req.nonce, keccak256(req.data)))
        ).recover(signature);

        return nonces(req.from) == req.nonce && signer == req.from;
    }
    
    /* ========== GAS VALIDATION ========== */
    
    /**
     * @notice Validates gas limit for a transaction
     * @dev Supports both default validation and advanced gas manager validation.
     *      Falls back gracefully if gas manager is unavailable.
     * @param requestedGas Amount of gas requested for the transaction
     * @param data Transaction calldata for function-specific validation
     * @return bool True if gas amount is within allowed limits
     * @custom:validation Basic check: 21000 <= gas <= defaultMaxGas
     * @custom:advanced Uses gas manager for function-specific limits if available
     * @custom:fallback Graceful degradation if gas manager call fails
     */
    function validateGas(uint256 requestedGas, bytes calldata data) public view returns (bool) {
        if (!gasValidationEnabled) {
            return true;
        }
        
        // Basic validation: minimum gas for transaction
        if (requestedGas < 21000 || requestedGas > defaultMaxGas) {
            return false;
        }
        
        // Advanced validation via gas manager if configured
        if (gasManager != address(0)) {
            try this._validateGasWithManager(requestedGas, data) returns (bool isValid) {
                return isValid;
            } catch {
                // Graceful fallback to default validation
                return requestedGas <= defaultMaxGas;
            }
        }
        
        return true;
    }
    
    /**
     * @dev Internal function to validate gas with external gas manager
     * @param requestedGas Amount of gas requested
     * @param data Transaction calldata to extract function selector
     * @return bool True if gas manager approves the gas amount
     * @custom:internal Only callable by this contract for security
     * @custom:external Calls gas manager's validateGasLimit function
     */
    function _validateGasWithManager(uint256 requestedGas, bytes calldata data) external view returns (bool) {
        require(msg.sender == address(this), "Internal function");
        
        if (data.length >= 4) {
            bytes4 functionSelector = bytes4(data[0:4]);
            
            // Static call to gas manager for validation
            (bool success, bytes memory result) = gasManager.staticcall(
                abi.encodeWithSignature("validateGasLimit(uint256,bytes4)", requestedGas, functionSelector)
            );
            
            if (success && result.length >= 32) {
                return abi.decode(result, (bool));
            }
        }
        
        // Fallback to default validation
        return requestedGas <= defaultMaxGas;
    }

    /* ========== TRANSACTION EXECUTION ========== */
    
    /**
     * @notice Executes a signed transaction on behalf of a user (gasless for the user)
     * @dev Validates signature and gas limits before execution. Implements ERC-2771 standard.
     *      Only authorized callers can execute transactions.
     * @param req ForwardRequest containing transaction details
     * @param signature User's signature authorizing the transaction
     * @return success Whether the target call succeeded
     * @return returndata Data returned from the target call
     * @custom:security Validates signature, gas limits, and prevents insufficient gas attacks
     * @custom:gasless User pays no gas fees - paymaster covers transaction costs
     * @custom:erc-two-seven-seven-one Appends user address to calldata for trusted forwarder pattern
     * @custom:events Emits ForwardedTransaction event
     */
    function execute(ForwardRequest calldata req, bytes calldata signature) 
        external 
        payable 
        onlyAuthorized 
        returns (bool, bytes memory) 
    {
        require(verify(req, signature), "SimpleForwarder: signature does not match request");
        require(validateGas(req.gas, req.data), "SimpleForwarder: gas limit exceeded");
        
        // Use nonce to prevent replay attacks
        _useNonce(req.from);

        // Execute transaction with ERC-2771 pattern (append user address)
        (bool success, bytes memory returndata) = req.to.call{gas: req.gas, value: req.value}(
            abi.encodePacked(req.data, req.from)
        );

        // Prevent insufficient gas attacks
        // Reference: https://ronan.eth.limo/blog/ethereum-gas-dangers/
        if (gasleft() <= req.gas / 63) {
            // Consume all remaining gas to prevent griefing
            /// @solidity memory-safe-assembly
            assembly {
                invalid()
            }
        }

        emit ForwardedTransaction(req.from, req.to, success, returndata);
        return (success, returndata);
    }

    /* ========== UTILITY FUNCTIONS ========== */
    
    /**
     * @notice Gets the current nonce for a given address
     * @dev Nonces prevent replay attacks and ensure transaction ordering
     * @param from Address to get nonce for
     * @return uint256 Current nonce value
     */
    function getNonce(address from) external view returns (uint256) {
        return nonces(from);
    }

    /**
     * @notice Checks if this forwarder is trusted by a target contract
     * @dev Attempts to call isTrustedForwarder on target contract
     * @param target Contract address to check
     * @return bool True if target contract trusts this forwarder
     * @custom:compatibility Gracefully handles non-ERC2771 contracts
     */
    function isTrustedForwarder(address target) external view returns (bool) {
        try ERC2771Context(target).isTrustedForwarder(address(this)) returns (bool trusted) {
            return trusted;
        } catch {
            return false;
        }
    }

    /**
     * @notice Allows paymaster to withdraw ETH from the contract
     * @dev Used to recover ETH sent to the contract or withdraw gas payments
     * @param amount Amount of ETH to withdraw in wei
     * @custom:security Only paymaster can call, validates sufficient balance
     */
    function withdraw(uint256 amount) external onlyPaymaster {
        require(address(this).balance >= amount, "SimpleForwarder: insufficient balance");
        payable(paymaster).transfer(amount);
    }

    /**
     * @notice Allows the contract to receive ETH for gas payments
     * @dev Enables paymaster to fund the contract for transaction fees
     */
    receive() external payable {}
}