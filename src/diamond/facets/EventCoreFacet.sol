// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {LibAppStorage} from "src/diamond/LibAppStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/utils/Context.sol";
import "src/libraries/Structs.sol";
import "src/libraries/Constants.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import "src/interfaces/ITicketNFT.sol";

/// @title EventCoreFacet - Core event functionality facet
/// @author Lummy Protocol Team
/// @notice Handles core event operations including initialization and tier management
/// @dev Part of Diamond pattern implementation - ~20KB target size
contract EventCoreFacet is ReentrancyGuard, ERC2771Context {
    using LibAppStorage for LibAppStorage.AppStorage;

    /// @notice Custom errors for gas efficiency
    error OnlyFactoryCanCall();
    error OnlyOrganizerCanCall();
    error EventIsCancelled();
    error TicketNFTAlreadySet();
    error PriceNotPositive();
    error AvailableTicketsNotPositive();
    error InvalidMaxPerPurchase();
    error TierDoesNotExist();
    error AvailableLessThanSold();
    error EventAlreadyCancelled();
    error EventNotStarted();
    error MaxMarkupExceeded();
    error OrganizerFeeExceeded();

    /// @notice Constructor for ERC2771 context
    /// @param trustedForwarder Address of trusted forwarder for gasless transactions
    constructor(address trustedForwarder) ERC2771Context(trustedForwarder) {}

    /// @notice Initializes the event contract with basic parameters
    /// @param _organizer Address of the event organizer
    /// @param _name Name of the event
    /// @param _description Description of the event
    /// @param _date Unix timestamp of the event date
    /// @param _venue Venue location of the event
    /// @param _ipfsMetadata IPFS hash containing additional event metadata
    function initialize(
        address _organizer,
        string memory _name,
        string memory _description,
        uint256 _date,
        string memory _venue,
        string memory _ipfsMetadata
    ) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (msg.sender != s.factory) revert OnlyFactoryCanCall();
        
        s.organizer = _organizer;
        s.name = _name;
        s.description = _description;
        s.date = _date;
        s.venue = _venue;
        s.ipfsMetadata = _ipfsMetadata;
        s.eventCreatedAt = block.timestamp;
        
        // Set organizer with maximum privileges
        s.staffRoles[_organizer] = LibAppStorage.StaffRole.MANAGER;
        s.staffWhitelist[_organizer] = true;
        
        // Configure default resale marketplace rules
        s.resaleRules = Structs.ResaleRules({
            allowResell: true,
            maxMarkupPercentage: Constants.DEFAULT_MAX_MARKUP_PERCENTAGE,
            organizerFeePercentage: 250, // 2.5%
            restrictResellTiming: false,
            minDaysBeforeEvent: 1,
            requireVerification: false
        });

        emit EventInitialized(_organizer, _name, _date);
    }

    /// @notice Sets the ticket NFT contract and related dependencies
    /// @param _ticketNFT Address of the deployed TicketNFT contract
    /// @param _idrxToken Address of the IDRX token contract for payments
    /// @param _platformFeeReceiver Address that receives platform fees
    function setTicketNFT(address _ticketNFT, address _idrxToken, address _platformFeeReceiver) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (msg.sender != s.factory) revert OnlyFactoryCanCall();
        if (address(s.ticketNFT) != address(0)) revert TicketNFTAlreadySet();
        
        s.ticketNFT = ITicketNFT(_ticketNFT);
        s.idrxToken = IERC20(_idrxToken);
        s.platformFeeReceiver = _platformFeeReceiver;

        emit TicketNFTSet(_ticketNFT, _idrxToken, _platformFeeReceiver);
    }

    /// @notice Creates a new ticket tier for the event
    /// @param _name Human-readable name for the ticket tier
    /// @param _price Price per ticket in IDRX tokens (wei)
    /// @param _available Total number of tickets available for this tier
    /// @param _maxPerPurchase Maximum tickets one address can buy in single transaction
    function addTicketTier(
        string memory _name,
        uint256 _price,
        uint256 _available,
        uint256 _maxPerPurchase
    ) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (_msgSender() != s.organizer) revert OnlyOrganizerCanCall();
        if (s.cancelled) revert EventIsCancelled();
        
        if (_price <= 0) revert PriceNotPositive();
        if (_available <= 0) revert AvailableTicketsNotPositive();
        if (_maxPerPurchase <= 0 || _maxPerPurchase > _available) revert InvalidMaxPerPurchase();
        
        uint256 tierId = s.tierCount;
        s.ticketTiers[tierId] = Structs.TicketTier({
            name: _name,
            price: _price,
            available: _available,
            sold: 0,
            maxPerPurchase: _maxPerPurchase,
            active: true
        });
        
        s.tierCount++;
        
        emit TicketTierAdded(tierId, _name, _price);
    }

    /// @notice Updates an existing ticket tier configuration
    /// @param _tierId ID of the tier to update
    /// @param _name New name for the ticket tier
    /// @param _price New price per ticket in IDRX tokens (wei)
    /// @param _available New total number of available tickets
    /// @param _maxPerPurchase New maximum tickets per transaction
    function updateTicketTier(
        uint256 _tierId,
        string memory _name,
        uint256 _price,
        uint256 _available,
        uint256 _maxPerPurchase
    ) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (_msgSender() != s.organizer) revert OnlyOrganizerCanCall();
        if (s.cancelled) revert EventIsCancelled();
        
        if (_tierId >= s.tierCount) revert TierDoesNotExist();
        Structs.TicketTier storage tier = s.ticketTiers[_tierId];
        
        if (_price <= 0) revert PriceNotPositive();
        if (_available < tier.sold) revert AvailableLessThanSold();
        if (_maxPerPurchase <= 0 || _maxPerPurchase > _available) revert InvalidMaxPerPurchase();
        
        tier.name = _name;
        tier.price = _price;
        tier.available = _available;
        tier.maxPerPurchase = _maxPerPurchase;
        
        emit TicketTierUpdated(_tierId, _name, _price, _available);
    }

    /// @notice Sets the algorithm mode for the event
    /// @param _useAlgorithm1 True for Algorithm 1 (escrow), false for Original
    /// @param _eventId Event ID for Algorithm 1 (ignored for Original)
    function setAlgorithm1(bool _useAlgorithm1, uint256 _eventId) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (msg.sender != s.factory) revert OnlyFactoryCanCall();
        if (s.algorithmLocked) revert LibAppStorage.AlgorithmIsLocked();
        
        s.useAlgorithm1 = _useAlgorithm1;
        if (_useAlgorithm1) {
            s.eventId = _eventId;
        }

        emit AlgorithmSet(_useAlgorithm1, _eventId);
    }

    /// @notice Permanently locks the algorithm to prevent mid-event changes
    function lockAlgorithm() external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (_msgSender() != s.organizer) revert OnlyOrganizerCanCall();
        
        s.algorithmLocked = true;
        emit AlgorithmLocked();
    }

    /// @notice Configures resale marketplace rules for the event
    /// @param _maxMarkupPercentage Maximum markup percentage in basis points
    /// @param _organizerFeePercentage Organizer fee percentage in basis points
    /// @param _restrictResellTiming Whether to enforce timing restrictions
    /// @param _minDaysBeforeEvent Minimum days before event for resale cutoff
    function setResaleRules(
        uint256 _maxMarkupPercentage,
        uint256 _organizerFeePercentage,
        bool _restrictResellTiming,
        uint256 _minDaysBeforeEvent
    ) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (_msgSender() != s.organizer) revert OnlyOrganizerCanCall();
        
        if (_maxMarkupPercentage > 5000) revert MaxMarkupExceeded(); // 50%
        if (_organizerFeePercentage > 1000) revert OrganizerFeeExceeded(); // 10%
        
        s.resaleRules.maxMarkupPercentage = _maxMarkupPercentage;
        s.resaleRules.organizerFeePercentage = _organizerFeePercentage;
        s.resaleRules.restrictResellTiming = _restrictResellTiming;
        s.resaleRules.minDaysBeforeEvent = _minDaysBeforeEvent;
        
        emit ResaleRulesUpdated(_maxMarkupPercentage, _organizerFeePercentage);
    }

    /// @notice Cancels the event and processes automatic refunds
    function cancelEvent() external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (_msgSender() != s.organizer) revert OnlyOrganizerCanCall();
        if (s.cancelled) revert EventAlreadyCancelled();
        if (block.timestamp >= s.date) revert EventNotStarted();
        
        s.cancelled = true;
        
        emit EventCancelled();
    }

    /// @notice Marks the event as completed after it has finished
    function markEventCompleted() external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (_msgSender() != s.organizer) revert OnlyOrganizerCanCall();
        
        require(block.timestamp >= s.date + 1 days, "Event not yet completed");
        require(!s.cancelled, "Cannot complete cancelled event");
        
        s.eventCompleted = true;
        
        emit EventCompleted();
    }

    /// @notice Gets the address of the associated TicketNFT contract
    /// @return Address of the TicketNFT contract
    function getTicketNFT() external view returns (address) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return address(s.ticketNFT);
    }

    /// @notice Gets basic event information
    /// @return name Event name
    /// @return description Event description
    /// @return date Event date timestamp
    /// @return venue Event venue
    /// @return organizer Event organizer address
    function getEventInfo() external view returns (
        string memory name,
        string memory description,
        uint256 date,
        string memory venue,
        address organizer
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return (s.name, s.description, s.date, s.venue, s.organizer);
    }

    /// @notice Gets event status flags
    /// @return cancelled Whether event is cancelled
    /// @return completed Whether event is completed
    /// @return useAlgorithm1 Whether using Algorithm 1
    /// @return algorithmLocked Whether algorithm is locked
    function getEventStatus() external view returns (
        bool cancelled,
        bool completed,
        bool useAlgorithm1,
        bool algorithmLocked
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return (s.cancelled, s.eventCompleted, s.useAlgorithm1, s.algorithmLocked);
    }

    /// @notice Gets ticket tier information
    /// @param tierId ID of the tier to query
    /// @return Ticket tier struct
    function getTicketTier(uint256 tierId) external view returns (Structs.TicketTier memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (tierId >= s.tierCount) revert TierDoesNotExist();
        return s.ticketTiers[tierId];
    }

    /// @notice Gets the total number of ticket tiers
    /// @return Number of tiers created
    function getTierCount() external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.tierCount;
    }

    /// @notice Gets resale rules for the event
    /// @return Resale rules struct
    function getResaleRules() external view returns (Structs.ResaleRules memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.resaleRules;
    }

    /// @notice ERC2771 context override for meta-transactions
    function _msgSender() internal view override returns (address) {
        return ERC2771Context._msgSender();
    }

    /// @notice ERC2771 context override for meta-transactions
    function _msgData() internal view override returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @notice ERC2771 context override for meta-transactions
    function _contextSuffixLength() internal view virtual override returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }

    // Events
    event EventInitialized(address indexed organizer, string name, uint256 date);
    event TicketNFTSet(address indexed ticketNFT, address indexed idrxToken, address indexed platformFeeReceiver);
    event TicketTierAdded(uint256 indexed tierId, string name, uint256 price);
    event TicketTierUpdated(uint256 indexed tierId, string name, uint256 price, uint256 available);
    event AlgorithmSet(bool useAlgorithm1, uint256 eventId);
    event AlgorithmLocked();
    event ResaleRulesUpdated(uint256 maxMarkupPercentage, uint256 organizerFeePercentage);
    event EventCancelled();
    event EventCompleted();
}