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

// Custom errors to reduce bytecode size
error InvalidAddress();
error EventDateMustBeInFuture();

contract EventFactory is IEventFactory, ERC2771Context, ReentrancyGuard, Ownable {
    // State variables
    address[] public events;
    address public idrxToken;
    address public platformFeeReceiver;
    EventDeployer public deployer;
    
    // Algorithm 1 specific
    mapping(uint256 => address) public eventContracts;
    uint256 public eventCounter;
    bool public algorithm1Enabled = true;
    
    // Constructor
    constructor(address _idrxToken, address _trustedForwarder) 
        ERC2771Context(_trustedForwarder) 
        Ownable(msg.sender) {
        if(_idrxToken == address(0)) revert InvalidAddress();
        idrxToken = _idrxToken;
        platformFeeReceiver = msg.sender;
        deployer = new EventDeployer();
    }
    
    // Create a new event - anyone can call this
    function createEvent(
        string calldata _name,
        string calldata _description,
        uint256 _date,
        string calldata _venue,
        string calldata _ipfsMetadata
    ) external override returns (address) {
        return createEvent(_name, _description, _date, _venue, _ipfsMetadata, false);
    }
    
    // Create event with algorithm selection
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
            // Algorithm 1: Pure Web3 approach
            uint256 eventId = eventCounter;
            eventCounter++;
            
            // Create deploy parameters struct
            EventDeployer.DeployParams memory params = EventDeployer.DeployParams({
                sender: _msgSender(), // Use meta transaction sender
                name: _name,
                description: _description,
                date: _date,
                venue: _venue,
                ipfsMetadata: _ipfsMetadata,
                idrxToken: idrxToken,
                platformFeeReceiver: platformFeeReceiver,
                useAlgorithm1: true,
                eventId: eventId
            });
            
            // Use the deployer contract to create event and ticket
            (address eventAddress,) = deployer.deployEventAndTicket(params);
            
            // Store for Algorithm 1
            eventContracts[eventId] = eventAddress;
            
            // Add to events list
            events.push(eventAddress);
            
            emit EventCreated(eventId, eventAddress);
            
            return eventAddress;
        } else {
            // Original algorithm
            // Create deploy parameters struct
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
                eventId: 0
            });
            
            // Use the deployer contract to create event and ticket
            (address eventAddress,) = deployer.deployEventAndTicket(params);
            
            // Add to events list
            events.push(eventAddress);
            
            emit EventCreated(events.length - 1, eventAddress);
            
            return eventAddress;
        }
    }
    
    // Get all events
    function getEvents() external view override returns (address[] memory) {
        return events;
    }
    
    // Get event details
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
    
    // Set platform fee receiver
    function setPlatformFeeReceiver(address receiver) external override onlyOwner {
        if(receiver == address(0)) revert InvalidAddress();
        platformFeeReceiver = receiver;
        
        emit PlatformFeeReceiverUpdated(receiver);
    }
    
    // Get platform fee percentage
    function getPlatformFeePercentage() external pure override returns (uint256) {
        return Constants.PLATFORM_FEE_PERCENTAGE;
    }
    
    // Update IDRX token address
    function updateIDRXToken(address _newToken) external onlyOwner {
        if(_newToken == address(0)) revert InvalidAddress();
        idrxToken = _newToken;
        
        emit IDRXTokenUpdated(_newToken);
    }
    
    // Algorithm 1 functions
    function getEventContract(uint256 eventId) external view returns (address) {
        return eventContracts[eventId];
    }
    
    function toggleAlgorithm1(bool _enabled) external onlyOwner {
        algorithm1Enabled = _enabled;
    }
    
    // Override _msgSender for ERC2771Context
    function _msgSender() internal view override(Context, ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }
    
    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
    
    function _contextSuffixLength() internal view virtual override(Context, ERC2771Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }
    
    // Events
    event EventCreated(uint256 indexed eventId, address indexed eventContract);
    event PlatformFeeReceiverUpdated(address indexed receiver);
    event IDRXTokenUpdated(address indexed newToken);
}