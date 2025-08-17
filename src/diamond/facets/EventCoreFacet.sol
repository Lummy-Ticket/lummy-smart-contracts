// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {LibAppStorage} from "src/diamond/LibAppStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/utils/Context.sol";
import "src/shared/libraries/Structs.sol";
import "src/shared/libraries/Constants.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import "src/shared/interfaces/ITicketNFT.sol";

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

    /// @notice Initializes the event contract with basic parameters (updated dengan category)
    /// @param _organizer Address of the event organizer
    /// @param _name Name of the event
    /// @param _description Description of the event
    /// @param _date Unix timestamp of the event date
    /// @param _venue Venue location of the event
    /// @param _ipfsMetadata IPFS hash containing additional event metadata
    /// @param _category Event category (e.g., "Music", "Sports", "Technology")
    function initialize(
        address _organizer,
        string memory _name,
        string memory _description,
        uint256 _date,
        string memory _venue,
        string memory _ipfsMetadata,
        string memory _category
    ) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (msg.sender != s.factory) revert OnlyFactoryCanCall();
        
        // NEW: Check if already initialized to prevent storage corruption
        require(bytes(s.name).length == 0, "Event already initialized");
        
        // NEW: Clear any existing tier data to prevent corruption
        _clearAllEventData(s);
        
        // Initialize event data
        s.organizer = _organizer;
        s.name = _name;
        s.description = _description;
        s.date = _date;
        s.venue = _venue;
        s.ipfsMetadata = _ipfsMetadata;
        s.category = _category;
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

    /// @notice Creates a new ticket tier for the event (updated dengan description & benefits)
    /// @param _name Human-readable name for the ticket tier
    /// @param _price Price per ticket in IDRX tokens (wei)
    /// @param _available Total number of tickets available for this tier
    /// @param _maxPerPurchase Maximum tickets one address can buy in single transaction
    /// @param _description Description of what this tier includes
    /// @param _benefits JSON string of benefits array (e.g., '["Priority seating", "Meet & greet"]')
    function addTicketTier(
        string memory _name,
        uint256 _price,
        uint256 _available,
        uint256 _maxPerPurchase,
        string memory _description,
        string memory _benefits
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
            active: true,
            description: _description,  // Field baru
            benefits: _benefits         // Field baru
        });
        
        s.tierCount++;
        
        emit TicketTierAdded(tierId, _name, _price);
    }

    /// @notice Updates an existing ticket tier configuration (updated dengan field baru)
    /// @param _tierId ID of the tier to update
    /// @param _name New name for the ticket tier
    /// @param _price New price per ticket in IDRX tokens (wei)
    /// @param _available New total number of available tickets
    /// @param _maxPerPurchase New maximum tickets per transaction
    /// @param _description New description for the tier
    /// @param _benefits New benefits JSON string
    function updateTicketTier(
        uint256 _tierId,
        string memory _name,
        uint256 _price,
        uint256 _available,
        uint256 _maxPerPurchase,
        string memory _description,
        string memory _benefits
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
        tier.description = _description;  // Update field baru
        tier.benefits = _benefits;        // Update field baru
        
        emit TicketTierUpdated(_tierId, _name, _price, _available);
    }

    /// @notice Sets the event ID for deterministic token generation
    /// @param _eventId Unique event ID for Algorithm 1 token generation
    function setEventId(uint256 _eventId) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (msg.sender != s.factory) revert OnlyFactoryCanCall();
        
        s.eventId = _eventId;
        emit EventIdSet(_eventId);
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

    /// @notice Clears all ticket tiers (untuk reset sebelum buat event baru)
    /// @dev Fungsi ini penting untuk fix masalah "Tier code too large" karena tierCount ga pernah reset
    function clearAllTiers() external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (_msgSender() != s.organizer) revert OnlyOrganizerCanCall();
        
        // Hapus semua tier data dan reset counter
        for (uint256 i = 0; i < s.tierCount; i++) {
            delete s.ticketTiers[i];
        }
        s.tierCount = 0;
        
        emit TiersCleared();
    }

    /// @notice Gets the address of the associated TicketNFT contract
    /// @return Address of the TicketNFT contract
    function getTicketNFT() external view returns (address) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return address(s.ticketNFT);
    }

    /// @notice Gets basic event information (updated dengan category)
    /// @return name Event name
    /// @return description Event description
    /// @return date Event date timestamp
    /// @return venue Event venue
    /// @return category Event category
    /// @return organizer Event organizer address
    function getEventInfo() external view returns (
        string memory name,
        string memory description,
        uint256 date,
        string memory venue,
        string memory category,
        address organizer
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return (s.name, s.description, s.date, s.venue, s.category, s.organizer);
    }

    /// @notice Gets event status flags
    /// @return cancelled Whether event is cancelled
    /// @return completed Whether event is completed
    function getEventStatus() external view returns (
        bool cancelled,
        bool completed
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return (s.cancelled, s.eventCompleted);
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

    /// @notice Gets IPFS metadata hash for the event (untuk NFT image generation)
    /// @return IPFS hash string
    function getIPFSMetadata() external view returns (string memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.ipfsMetadata;
    }

    // ========== PHASE 2: NFT TIER IMAGE MANAGEMENT ==========

    /// @notice Sets tier-specific NFT background images during event initialization
    /// @param tierImageHashes Array of IPFS hashes for tier background images
    function setTierImages(string[] memory tierImageHashes) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        require(msg.sender == s.organizer, "Only organizer can call");
        
        // Clear existing tier images
        for (uint256 i = 0; i < s.tierImageCount; i++) {
            delete s.tierImageHashes[i];
        }
        
        // Set new tier images
        for (uint256 i = 0; i < tierImageHashes.length; i++) {
            s.tierImageHashes[i] = tierImageHashes[i];
        }
        s.tierImageCount = tierImageHashes.length;
        
        emit TierImagesUpdated(tierImageHashes.length);
    }

    /// @notice Sets a single tier image hash
    /// @param tierIndex Index of the tier (0-based)
    /// @param imageHash IPFS hash of the tier background image
    function setTierImageHash(uint256 tierIndex, string memory imageHash) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        require(msg.sender == s.organizer, "Only organizer can call");
        require(tierIndex < s.tierCount, "Tier index out of bounds");
        
        s.tierImageHashes[tierIndex] = imageHash;
        
        // Update count if this is a new tier image
        if (tierIndex >= s.tierImageCount) {
            s.tierImageCount = tierIndex + 1;
        }
        
        emit TierImageUpdated(tierIndex, imageHash);
    }

    /// @notice Gets tier-specific NFT background image hash
    /// @param tierIndex Index of the tier (0-based)
    /// @return IPFS hash of the tier background image
    function getTierImageHash(uint256 tierIndex) external view returns (string memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.tierImageHashes[tierIndex];
    }

    /// @notice Gets all tier image hashes for the event
    /// @return Array of IPFS hashes for all tier background images
    function getAllTierImageHashes() external view returns (string[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        string[] memory hashes = new string[](s.tierImageCount);
        
        for (uint256 i = 0; i < s.tierImageCount; i++) {
            hashes[i] = s.tierImageHashes[i];
        }
        
        return hashes;
    }

    /// @notice Gets the number of tier images stored
    /// @return Number of tier images
    function getTierImageCount() external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.tierImageCount;
    }

    // ========== PHASE 1.3: EFFICIENT ATTENDEE MANAGEMENT ==========
    

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

    /// @notice Internal function to clear all event data for clean initialization
    /// @param s AppStorage reference
    function _clearAllEventData(LibAppStorage.AppStorage storage s) internal {
        // Clear all tier data
        for (uint256 i = 0; i < s.tierCount; i++) {
            delete s.ticketTiers[i];
            delete s.tierSalesCount[i];
        }
        s.tierCount = 0;
        
        // Reset event flags
        s.cancelled = false;
        s.eventCompleted = false;
        
        // Clear revenue tracking
        s.totalRevenue = 0;
        s.totalRefunds = 0;
        s.platformFeesCollected = 0;
        s.platformFeesWithdrawn = 0;
        
        // NEW: Clear attendee tracking data (Phase 1.3)
        for (uint256 i = 0; i < s.attendeeList.length; i++) {
            address attendee = s.attendeeList[i];
            delete s.userTokenIds[attendee];
            delete s.isAttendee[attendee];
        }
        delete s.attendeeList;
        s.totalMintedTokens = 0;
        
        // Note: We don't clear s.organizer, s.name etc here as they will be set immediately after
        // Note: We don't clear staff roles as organizer will be set again with MANAGER role
    }

    // ========== PHASE 1.3: EFFICIENT ATTENDEE MANAGEMENT FUNCTIONS ==========

    /**
     * @notice Get all token IDs owned by a specific attendee (Phase 1.3 - EFFICIENT!)
     * @dev Replaces 5000+ contract calls with single call
     * @param attendee Address of the attendee
     * @return tokenIds Array of token IDs owned by the attendee
     */
    function getAttendeeTokens(address attendee) external view returns (uint256[] memory tokenIds) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.userTokenIds[attendee];
    }

    /**
     * @notice Get all event attendees (Phase 1.3 - ORGANIZER DASHBOARD)
     * @dev Single call to get all attendee addresses
     * @return attendees Array of all attendee addresses
     */
    function getAllAttendees() external view returns (address[] memory attendees) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.attendeeList;
    }

    /**
     * @notice Get real-time attendee statistics (Phase 1.3 - ANALYTICS)
     * @dev Instant analytics for organizer dashboard
     * @return totalAttendees Total number of unique attendees
     * @return totalTokensMinted Total number of tickets minted
     */
    function getAttendeeStats() external view returns (uint256 totalAttendees, uint256 totalTokensMinted) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        totalAttendees = s.attendeeList.length;
        totalTokensMinted = s.totalMintedTokens;
    }

    /**
     * @notice Check if address is an event attendee (Phase 1.3 - O(1) LOOKUP)
     * @dev Instant attendee verification for staff/access control
     * @param attendee Address to check
     * @return isAttendee True if address has purchased tickets
     */
    function isEventAttendee(address attendee) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.isAttendee[attendee];
    }

    /**
     * @notice Get comprehensive event analytics (Phase 1.3 - ORGANIZER INSIGHTS)
     * @dev Real-time event statistics for professional dashboard
     * @return totalTicketsSold Total tickets sold across all tiers
     * @return totalRevenue Total revenue generated (in IDRX wei)
     * @return uniqueAttendees Number of unique attendees
     * @return tierSalesCount Array of tickets sold per tier
     */
    function getEventAnalytics() external view returns (
        uint256 totalTicketsSold,
        uint256 totalRevenue,
        uint256 uniqueAttendees,
        uint256[] memory tierSalesCount
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        totalRevenue = s.totalRevenue;
        uniqueAttendees = s.attendeeList.length;
        
        // Calculate total tickets sold and prepare tier sales array
        tierSalesCount = new uint256[](s.tierCount);
        for (uint256 i = 0; i < s.tierCount; i++) {
            tierSalesCount[i] = s.tierSalesCount[i];
            totalTicketsSold += s.ticketTiers[i].sold;
        }
    }

    // Events
    event EventInitialized(address indexed organizer, string name, uint256 date);
    event TicketNFTSet(address indexed ticketNFT, address indexed idrxToken, address indexed platformFeeReceiver);
    event TicketTierAdded(uint256 indexed tierId, string name, uint256 price);
    event TicketTierUpdated(uint256 indexed tierId, string name, uint256 price, uint256 available);
    event EventIdSet(uint256 eventId);
    event ResaleRulesUpdated(uint256 maxMarkupPercentage, uint256 organizerFeePercentage);
    event EventCancelled();
    event EventCompleted();
    event TiersCleared(); // Event untuk track kapan tier di-reset
    
    // Phase 2: NFT Tier Image Events
    event TierImagesUpdated(uint256 tierImageCount);
    event TierImageUpdated(uint256 indexed tierIndex, string imageHash);
}