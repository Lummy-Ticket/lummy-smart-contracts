// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {Context} from "@openzeppelin/utils/Context.sol";
import "src/libraries/Structs.sol";
import "src/libraries/Constants.sol";
import "src/interfaces/IEventFactory.sol";
import "src/core/Event.sol";
import "src/core/EventDeployer.sol";

/**
 * @dev Gas-efficient custom errors for EventFactory operations
 */
error InvalidAddress(); /// @dev Thrown when zero address is provided where valid address required
error EventDateMustBeInFuture(); /// @dev Thrown when event date is not in the future

/**
 * @title EventFactory Contract
 * @author Lummy Protocol Team
 * @notice Factory contract for creating and managing events with dual algorithm support
 * @dev Supports both Algorithm 1 (escrow-based) and Original (immediate payment) modes.
 *      Implements ERC-2771 for gasless transactions and comprehensive gas management.
 * @custom:version 2.0.0
 * @custom:security-contact security@lummy.io
 */
contract EventFactory is IEventFactory, ERC2771Context, ReentrancyGuard, Ownable {
    
    /* ========== STATE VARIABLES ========== */
    
    /// @notice Array of all created event addresses
    address[] public events;
    
    /// @notice IDRX token contract used for all payments
    address public idrxToken;
    
    /// @notice Address that receives platform fees
    address public platformFeeReceiver;
    
    /// @notice Deployer contract for creating events and NFTs
    EventDeployer public deployer;
    
    /// @dev Internal trusted forwarder address for ERC-2771
    address private _trustedForwarder;
    
    /* ========== GAS MANAGEMENT ========== */
    
    /// @notice Maximum gas limit for meta-transactions
    uint256 public maxGasLimit = 500000;
    
    /// @notice Gas buffer to prevent out-of-gas errors
    uint256 public gasBuffer = 50000;
    
    /// @dev Maps function selectors to their specific gas limits
    mapping(bytes4 => uint256) public functionGasLimits;
    
    /* ========== ALGORITHM 1 VARIABLES ========== */
    
    /// @dev Maps Algorithm 1 event IDs to their contract addresses
    mapping(uint256 => address) public eventContracts;
    
    /// @notice Counter for generating unique Algorithm 1 event IDs
    uint256 public eventCounter;
    
    /// @notice Whether Algorithm 1 is enabled for new events
    bool public algorithm1Enabled = true;
    
    /* ========== CONSTRUCTOR ========== */
    
    /**
     * @notice Initializes the EventFactory with required dependencies
     * @dev Sets up ERC-2771 context, deploys EventDeployer, and configures initial settings
     * @param _idrxToken Address of the IDRX token contract for payments
     * @param trustedForwarderAddress Address of the trusted forwarder for gasless transactions
     * @custom:security Validates that IDRX token address is not zero
     */
    constructor(address _idrxToken, address trustedForwarderAddress) 
        ERC2771Context(trustedForwarderAddress) 
        Ownable(msg.sender) {
        if(_idrxToken == address(0)) revert InvalidAddress();
        idrxToken = _idrxToken;
        platformFeeReceiver = msg.sender;
        _trustedForwarder = trustedForwarderAddress;
        deployer = new EventDeployer();
    }
    
    /* ========== EVENT CREATION ========== */
    
    /**
     * @notice Creates a new event using the Original algorithm (immediate payment)
     * @dev Public interface that delegates to the overloaded createEvent function
     * @param _name Name of the event
     * @param _description Description of the event
     * @param _date Unix timestamp of the event date
     * @param _venue Venue location of the event
     * @param _ipfsMetadata IPFS hash containing additional event metadata
     * @return address Address of the created Event contract
     * @custom:algorithm Uses Original algorithm (immediate payment to organizer)
     */
    function createEvent(
        string calldata _name,
        string calldata _description,
        uint256 _date,
        string calldata _venue,
        string calldata _ipfsMetadata
    ) external override returns (address) {
        return createEvent(_name, _description, _date, _venue, _ipfsMetadata, false);
    }
    
    /**
     * @notice Creates a new event with algorithm selection
     * @dev Main event creation function supporting both algorithms.
     *      Protected by reentrancy guard and validates event date.
     * @param _name Name of the event
     * @param _description Description of the event
     * @param _date Unix timestamp of the event date (must be in future)
     * @param _venue Venue location of the event
     * @param _ipfsMetadata IPFS hash containing additional event metadata
     * @param _useAlgorithm1 True for Algorithm 1 (escrow), false for Original (immediate)
     * @return address Address of the created Event contract
     * @custom:security Protected by nonReentrant modifier
     * @custom:validation Event date must be in the future
     * @custom:algorithm-one Creates escrow-based event with deterministic token IDs
     * @custom:original-algorithm Creates immediate payment event with sequential token IDs
     * @custom:events Emits EventCreated event
     */
    function createEvent(
        string calldata _name,
        string calldata _description,
        uint256 _date,
        string calldata _venue,
        string calldata _ipfsMetadata,
        bool _useAlgorithm1
    ) public nonReentrant returns (address) {
        if(_date <= block.timestamp) revert EventDateMustBeInFuture();
        
        if (_useAlgorithm1 && algorithm1Enabled) {
            // Algorithm 1: Escrow-based event creation
            uint256 eventId = eventCounter;
            eventCounter++;
            
            EventDeployer.DeployParams memory params = EventDeployer.DeployParams({
                sender: _msgSender(),
                name: _name,
                description: _description,
                date: _date,
                venue: _venue,
                ipfsMetadata: _ipfsMetadata,
                idrxToken: idrxToken,
                platformFeeReceiver: platformFeeReceiver,
                useAlgorithm1: true,
                eventId: eventId,
                trustedForwarder: _trustedForwarder
            });
            
            (address eventAddress,) = deployer.deployEventAndTicket(params);
            
            // Store Algorithm 1 mapping
            eventContracts[eventId] = eventAddress;
            events.push(eventAddress);
            
            emit EventCreated(eventId, eventAddress);
            return eventAddress;
        } else {
            // Original algorithm: Immediate payment event creation
            EventDeployer.DeployParams memory params = EventDeployer.DeployParams({
                sender: _msgSender(),
                name: _name,
                description: _description,
                date: _date,
                venue: _venue,
                ipfsMetadata: _ipfsMetadata,
                idrxToken: idrxToken,
                platformFeeReceiver: platformFeeReceiver,
                useAlgorithm1: false,
                eventId: 0,
                trustedForwarder: _trustedForwarder
            });
            
            (address eventAddress,) = deployer.deployEventAndTicket(params);
            events.push(eventAddress);
            
            emit EventCreated(events.length - 1, eventAddress);
            return eventAddress;
        }
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    /**
     * @notice Returns array of all created event contract addresses
     * @return address[] Array of event contract addresses
     */
    function getEvents() external view override returns (address[] memory) {
        return events;
    }
    
    /**
     * @notice Retrieves detailed information about a specific event
     * @param eventAddress Address of the event contract to query
     * @return Structs.EventDetails Structured event information
     */
    function getEventDetails(address eventAddress) external view override returns (Structs.EventDetails memory) {
        Event eventContract = Event(eventAddress);
        
        return Structs.EventDetails({
            name: eventContract.name(),
            description: eventContract.description(),
            date: eventContract.date(),
            venue: eventContract.venue(),
            ipfsMetadata: eventContract.ipfsMetadata(),
            organizer: eventContract.organizer()
        });
    }
    
    /* ========== ADMIN FUNCTIONS ========== */
    
    /**
     * @notice Updates the platform fee receiver address
     * @dev Only owner can update. Validates address is not zero.
     * @param receiver New platform fee receiver address
     * @custom:security Only owner can call
     * @custom:events Emits PlatformFeeReceiverUpdated event
     */
    function setPlatformFeeReceiver(address receiver) external override onlyOwner {
        if(receiver == address(0)) revert InvalidAddress();
        platformFeeReceiver = receiver;
        
        emit PlatformFeeReceiverUpdated(receiver);
    }
    
    /**
     * @notice Updates the trusted forwarder for ERC-2771 gasless transactions
     * @dev Only owner can update. Used for meta-transaction support.
     * @param forwarder New trusted forwarder address
     * @custom:security Only owner can call
     * @custom:gasless Enables gasless transactions through the forwarder
     * @custom:events Emits TrustedForwarderUpdated event
     */
    function setTrustedForwarder(address forwarder) external onlyOwner {
        _trustedForwarder = forwarder;
        emit TrustedForwarderUpdated(forwarder);
    }
    
    /**
     * @notice Returns the current trusted forwarder address
     * @return address Current trusted forwarder address
     */
    function getTrustedForwarder() external view returns (address) {
        return _trustedForwarder;
    }
    
    /* ========== GAS MANAGEMENT ========== */
    
    /**
     * @notice Sets the maximum gas limit for meta-transactions
     * @dev Must be greater than gas buffer and not exceed 1M gas
     * @param _maxGasLimit New maximum gas limit
     * @custom:security Validates gas limit boundaries
     * @custom:events Emits MaxGasLimitUpdated event
     */
    function setMaxGasLimit(uint256 _maxGasLimit) external onlyOwner {
        require(_maxGasLimit > gasBuffer, "Gas limit too low");
        require(_maxGasLimit <= 1000000, "Gas limit too high"); // Max 1M gas
        maxGasLimit = _maxGasLimit;
        emit MaxGasLimitUpdated(_maxGasLimit);
    }
    
    /**
     * @notice Sets the gas buffer to prevent out-of-gas errors
     * @dev Must be less than maximum gas limit
     * @param _gasBuffer New gas buffer amount
     * @custom:security Validates buffer is less than max gas limit
     * @custom:events Emits GasBufferUpdated event
     */
    function setGasBuffer(uint256 _gasBuffer) external onlyOwner {
        require(_gasBuffer < maxGasLimit, "Gas buffer too high");
        gasBuffer = _gasBuffer;
        emit GasBufferUpdated(_gasBuffer);
    }
    
    /**
     * @notice Sets custom gas limit for specific function
     * @dev Allows fine-tuned gas control per function selector
     * @param functionSelector 4-byte function selector
     * @param gasLimit Custom gas limit for this function
     * @custom:security Gas limit cannot exceed maximum
     * @custom:events Emits FunctionGasLimitUpdated event
     */
    function setFunctionGasLimit(bytes4 functionSelector, uint256 gasLimit) external onlyOwner {
        require(gasLimit <= maxGasLimit, "Exceeds maximum gas limit");
        functionGasLimits[functionSelector] = gasLimit;
        emit FunctionGasLimitUpdated(functionSelector, gasLimit);
    }
    
    /**
     * @notice Gets the gas limit for a specific function
     * @param functionSelector 4-byte function selector
     * @return uint256 Gas limit for the function (custom or default)
     */
    function getFunctionGasLimit(bytes4 functionSelector) external view returns (uint256) {
        uint256 customLimit = functionGasLimits[functionSelector];
        return customLimit > 0 ? customLimit : maxGasLimit;
    }
    
    /**
     * @notice Validates if requested gas is within allowed limits
     * @param requestedGas Amount of gas requested
     * @param functionSelector Function selector to check against
     * @return bool True if gas amount is valid
     */
    function validateGasLimit(uint256 requestedGas, bytes4 functionSelector) external view returns (bool) {
        uint256 allowedLimit = this.getFunctionGasLimit(functionSelector);
        return requestedGas <= allowedLimit && requestedGas >= gasBuffer;
    }
    
    /**
     * @notice Returns the platform fee percentage
     * @return uint256 Platform fee percentage in basis points
     */
    function getPlatformFeePercentage() external pure override returns (uint256) {
        return Constants.PLATFORM_FEE_PERCENTAGE;
    }
    
    /**
     * @notice Updates the IDRX token contract address
     * @dev Only owner can update. Validates address is not zero.
     * @param _newToken New IDRX token contract address
     * @custom:security Only owner can call
     * @custom:events Emits IDRXTokenUpdated event
     */
    function updateIDRXToken(address _newToken) external onlyOwner {
        if(_newToken == address(0)) revert InvalidAddress();
        idrxToken = _newToken;
        
        emit IDRXTokenUpdated(_newToken);
    }
    
    /* ========== ALGORITHM 1 FUNCTIONS ========== */
    
    /**
     * @notice Gets the event contract address for a specific Algorithm 1 event ID
     * @param eventId Algorithm 1 event identifier
     * @return address Event contract address
     */
    function getEventContract(uint256 eventId) external view returns (address) {
        return eventContracts[eventId];
    }
    
    /**
     * @notice Enables or disables Algorithm 1 for new events
     * @dev Only owner can toggle. Affects only new event creation.
     * @param _enabled True to enable Algorithm 1, false to disable
     * @custom:security Only owner can call
     */
    function toggleAlgorithm1(bool _enabled) external onlyOwner {
        algorithm1Enabled = _enabled;
    }
    
    /* ========== ERC2771 CONTEXT OVERRIDES ========== */
    
    /**
     * @dev Override _msgSender to support meta-transactions via ERC2771
     * @return address The actual sender of the transaction (may be different from tx.origin)
     */
    function _msgSender() internal view override(Context, ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }
    
    /**
     * @dev Override _msgData to support meta-transactions via ERC2771
     * @return bytes The actual calldata of the transaction
     */
    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
    
    /**
     * @dev Override _contextSuffixLength for ERC2771 compatibility
     * @return uint256 Length of the context suffix
     */
    function _contextSuffixLength() internal view virtual override(Context, ERC2771Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }
    
    /* ========== EVENTS ========== */
    
    /// @notice Emitted when a new event is created
    event EventCreated(uint256 indexed eventId, address indexed eventContract);
    
    /// @notice Emitted when platform fee receiver is updated
    event PlatformFeeReceiverUpdated(address indexed receiver);
    
    /// @notice Emitted when IDRX token address is updated
    event IDRXTokenUpdated(address indexed newToken);
    
    /// @notice Emitted when trusted forwarder is updated
    event TrustedForwarderUpdated(address indexed forwarder);
    
    /// @notice Emitted when maximum gas limit is updated
    event MaxGasLimitUpdated(uint256 newLimit);
    
    /// @notice Emitted when gas buffer is updated
    event GasBufferUpdated(uint256 newBuffer);
    
    /// @notice Emitted when function-specific gas limit is updated
    event FunctionGasLimitUpdated(bytes4 indexed functionSelector, uint256 gasLimit);
}