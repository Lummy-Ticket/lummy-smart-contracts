// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/utils/Context.sol";
import "src/libraries/Structs.sol";
import "src/libraries/Constants.sol";
import "src/libraries/TicketLib.sol";
import "src/interfaces/IEvent.sol";
import "src/interfaces/ITicketNFT.sol";
import "src/core/TicketNFT.sol";

/**
 * @dev Gas-efficient custom errors for Event contract operations
 */
error OnlyFactoryCanCall(); /// @dev Thrown when non-factory address attempts factory-only operations
error OnlyOrganizerCanCall(); /// @dev Thrown when non-organizer attempts organizer-only operations  
error EventIsCancelled(); /// @dev Thrown when operations are attempted on cancelled events
error TicketNFTAlreadySet(); /// @dev Thrown when attempting to set NFT contract twice
error PriceNotPositive(); /// @dev Thrown when ticket price is zero or negative
error AvailableTicketsNotPositive(); /// @dev Thrown when available ticket count is zero or negative
error InvalidMaxPerPurchase(); /// @dev Thrown when max per purchase exceeds available tickets
error TierDoesNotExist(); /// @dev Thrown when referencing non-existent ticket tier
error AvailableLessThanSold(); /// @dev Thrown when trying to set available tickets below sold count
error InvalidPurchaseRequest(); /// @dev Thrown when purchase request validation fails
error TokenTransferFailed(); /// @dev Thrown when IDRX token transfer fails
error PlatformFeeTransferFailed(); /// @dev Thrown when platform fee transfer fails
error OrganizerPaymentFailed(); /// @dev Thrown when organizer payment fails
error MaxMarkupExceeded(); /// @dev Thrown when resale markup exceeds maximum allowed
error OrganizerFeeExceeded(); /// @dev Thrown when organizer fee exceeds maximum allowed
error ResaleNotAllowed(); /// @dev Thrown when resale is disabled for the event
error NotTicketOwner(); /// @dev Thrown when non-owner attempts owner-only ticket operations
error TicketUsed(); /// @dev Thrown when attempting operations on used/scanned tickets
error PriceExceedsMaxAllowed(); /// @dev Thrown when resale price exceeds maximum markup
error TooCloseToEventDate(); /// @dev Thrown when resale timing restrictions are violated
error TicketNotListedForResale(); /// @dev Thrown when attempting to buy unlisted ticket
error PaymentFailed(); /// @dev Thrown when resale payment fails
error OrganizerFeeTransferFailed(); /// @dev Thrown when organizer resale fee transfer fails
error SellerPaymentFailed(); /// @dev Thrown when seller payment fails
error NotSeller(); /// @dev Thrown when non-seller attempts seller operations
error EventAlreadyCancelled(); /// @dev Thrown when attempting to cancel already cancelled event
error EventNotCompleted(); /// @dev Thrown when attempting post-event operations before completion
error NoFundsToWithdraw(); /// @dev Thrown when attempting to withdraw with zero balance
error WithdrawFailed(); /// @dev Thrown when organizer fund withdrawal fails
error EventNotStarted(); /// @dev Thrown when attempting cancellation after event start

/**
 * @title Event Contract
 * @author Lummy Protocol Team
 * @notice Main contract for managing events, ticket sales, and resale marketplace
 * @dev Implements ERC-2771 for gasless transactions, ReentrancyGuard for security,
 *      and role-based access control for staff management
 * @custom:version 2.0.0
 * @custom:security-contact security@lummy.io
 */
contract Event is IEvent, ERC2771Context, ReentrancyGuard, Ownable {
    
    /* ========== STATE VARIABLES ========== */
    
    /// @notice Basic event information
    string public name;
    string public description;
    uint256 public date;
    string public venue;
    string public ipfsMetadata;
    address public organizer;
    
    /// @notice Event status flags
    bool public cancelled;
    bool public eventCompleted;
    
    /// @dev Tracks organizer funds held in escrow until event completion
    mapping(address => uint256) public organizerEscrow;
    
    /* ========== ALGORITHM 1 VARIABLES ========== */
    
    /// @notice Unique identifier for Algorithm 1 events
    uint256 public eventId;
    
    /// @notice Flag indicating whether event uses Algorithm 1 or original algorithm
    bool public useAlgorithm1;
    
    /// @notice Prevents algorithm changes mid-event for security
    bool public algorithmLocked;
    
    /* ========== STAFF MANAGEMENT ========== */
    
    /**
     * @notice Hierarchical staff roles with increasing privileges
     * @dev Each role inherits permissions from lower roles
     */
    enum StaffRole { 
        NONE,       /// @dev No staff privileges
        SCANNER,    /// @dev Can scan/validate tickets
        CHECKIN,    /// @dev Can check-in attendees + SCANNER privileges
        MANAGER     /// @dev Can manage staff + CHECKIN privileges
    }
    
    /// @dev Maps staff addresses to their assigned roles
    mapping(address => StaffRole) public staffRoles;
    
    /// @dev Legacy staff whitelist for backward compatibility
    mapping(address => bool) public staffWhitelist;
    
    /// @dev Tracks existence of Algorithm 1 token IDs
    mapping(uint256 => bool) public ticketExists;
    
    /* ========== CONTRACT REFERENCES ========== */
    
    /// @notice Address of the factory contract that deployed this event
    address public factory;
    
    /// @notice NFT contract for minting and managing tickets
    ITicketNFT public ticketNFT;
    
    /// @notice IDRX token contract for payments
    IERC20 public idrxToken;
    
    /* ========== TICKET TIERS & RESALE ========== */
    
    /// @dev Maps tier IDs to their configuration
    mapping(uint256 => Structs.TicketTier) public ticketTiers;
    
    /// @notice Total number of ticket tiers created
    uint256 public tierCount;
    
    /// @notice Resale marketplace configuration
    Structs.ResaleRules public resaleRules;
    
    /// @dev Maps token IDs to their resale listing information
    mapping(uint256 => Structs.ListingInfo) public listings;
    
    /// @notice Address that receives platform fees
    address public platformFeeReceiver;
    
    /* ========== MODIFIERS ========== */
    
    /**
     * @dev Restricts function access to event organizer only
     * @notice Reverts with OnlyOrganizerCanCall if caller is not the organizer
     */
    modifier onlyOrganizer() {
        if(_msgSender() != organizer) revert OnlyOrganizerCanCall();
        _;
    }
    
    /**
     * @dev Enforces hierarchical role-based access control
     * @param requiredRole Minimum staff role required to execute function
     * @notice Reverts if caller doesn't have sufficient privileges
     */
    modifier onlyStaffRole(StaffRole requiredRole) {
        require(staffRoles[_msgSender()] >= requiredRole, "Insufficient staff privileges");
        _;
    }
    
    /**
     * @dev Prevents algorithm changes when locked
     * @notice Ensures algorithm cannot be modified mid-event for security
     */
    modifier algorithmNotLocked() {
        require(!algorithmLocked, "Algorithm is locked");
        _;
    }
    
    /**
     * @dev Legacy staff access modifier for backward compatibility
     * @notice Requires minimum SCANNER role privileges
     */
    modifier onlyStaff() {
        require(staffRoles[_msgSender()] >= StaffRole.SCANNER, "Only staff can call");
        _;
    }
    
    /**
     * @dev Ensures operations are only performed on active (non-cancelled) events
     * @notice Reverts with EventIsCancelled if event has been cancelled
     */
    modifier eventActive() {
        if(cancelled) revert EventIsCancelled();
        _;
    }
    
    /* ========== CONSTRUCTOR ========== */
    
    /**
     * @notice Initializes the Event contract with ERC-2771 support
     * @dev Sets factory as the deployer and initializes inherited contracts
     * @param trustedForwarder Address of the trusted forwarder for gasless transactions
     */
    constructor(address trustedForwarder) ERC2771Context(trustedForwarder) Ownable(msg.sender) {
        factory = msg.sender;
    }
    
    /* ========== INITIALIZATION FUNCTIONS ========== */
    
    /**
     * @notice Initializes the event contract with basic parameters
     * @dev Called by factory contract during deployment. Sets organizer with MANAGER role.
     * @param _organizer Address of the event organizer
     * @param _name Name of the event
     * @param _description Description of the event
     * @param _date Unix timestamp of the event date
     * @param _venue Venue location of the event
     * @param _ipfsMetadata IPFS hash containing additional event metadata
     * @custom:security Only factory can call this function
     */
    function initialize(
        address _organizer,
        string memory _name,
        string memory _description,
        uint256 _date,
        string memory _venue,
        string memory _ipfsMetadata
    ) external override {
        if(msg.sender != factory) revert OnlyFactoryCanCall();
        
        organizer = _organizer;
        name = _name;
        description = _description;
        date = _date;
        venue = _venue;
        ipfsMetadata = _ipfsMetadata;
        
        // Set organizer with maximum privileges
        staffWhitelist[_organizer] = true;
        staffRoles[_organizer] = StaffRole.MANAGER;
        
        // Configure default resale marketplace rules
        resaleRules = Structs.ResaleRules({
            allowResell: true,
            maxMarkupPercentage: Constants.DEFAULT_MAX_MARKUP_PERCENTAGE,
            organizerFeePercentage: 250, // 2.5%
            restrictResellTiming: false,
            minDaysBeforeEvent: 1,
            requireVerification: false
        });
    }
    
    /**
     * @notice Sets the ticket NFT contract and related dependencies
     * @dev Called by factory after NFT deployment. Transfers ownership to organizer.
     * @param _ticketNFT Address of the deployed TicketNFT contract
     * @param _idrxToken Address of the IDRX token contract for payments
     * @param _platformFeeReceiver Address that receives platform fees
     * @custom:security Only factory can call, and only once per event
     */
    function setTicketNFT(address _ticketNFT, address _idrxToken, address _platformFeeReceiver) external {
        if(msg.sender != factory) revert OnlyFactoryCanCall();
        if(address(ticketNFT) != address(0)) revert TicketNFTAlreadySet();
        
        ticketNFT = ITicketNFT(_ticketNFT);
        idrxToken = IERC20(_idrxToken);
        platformFeeReceiver = _platformFeeReceiver;
        
        // Transfer contract ownership to event organizer
        _transferOwnership(organizer);
    }
    
    /* ========== TICKET TIER MANAGEMENT ========== */
    
    /**
     * @notice Creates a new ticket tier for the event
     * @dev Only organizer can create tiers. Validates all parameters for consistency.
     * @param _name Human-readable name for the ticket tier
     * @param _price Price per ticket in IDRX tokens (wei)
     * @param _available Total number of tickets available for this tier
     * @param _maxPerPurchase Maximum tickets one address can buy in single transaction
     * @custom:security Input validation prevents common configuration errors
     * @custom:events Emits TicketTierAdded event
     */
    function addTicketTier(
        string memory _name,
        uint256 _price,
        uint256 _available,
        uint256 _maxPerPurchase
    ) external override onlyOrganizer eventActive {
        if(_price <= 0) revert PriceNotPositive();
        if(_available <= 0) revert AvailableTicketsNotPositive();
        if(_maxPerPurchase <= 0 || _maxPerPurchase > _available) revert InvalidMaxPerPurchase();
        
        uint256 tierId = tierCount;
        ticketTiers[tierId] = Structs.TicketTier({
            name: _name,
            price: _price,
            available: _available,
            sold: 0,
            maxPerPurchase: _maxPerPurchase,
            active: true
        });
        
        tierCount++;
        
        emit TicketTierAdded(tierId, _name, _price);
    }
    
    /**
     * @notice Updates an existing ticket tier configuration
     * @dev Validates that available tickets >= sold tickets to prevent overselling
     * @param _tierId ID of the tier to update
     * @param _name New name for the ticket tier
     * @param _price New price per ticket in IDRX tokens (wei)
     * @param _available New total number of available tickets
     * @param _maxPerPurchase New maximum tickets per transaction
     * @custom:security Prevents reducing available below sold count
     * @custom:events Emits TicketTierUpdated event
     */
    function updateTicketTier(
        uint256 _tierId,
        string memory _name,
        uint256 _price,
        uint256 _available,
        uint256 _maxPerPurchase
    ) external override onlyOrganizer eventActive {
        if(_tierId >= tierCount) revert TierDoesNotExist();
        Structs.TicketTier storage tier = ticketTiers[_tierId];
        
        if(_price <= 0) revert PriceNotPositive();
        if(_available < tier.sold) revert AvailableLessThanSold();
        if(_maxPerPurchase <= 0 || _maxPerPurchase > _available) revert InvalidMaxPerPurchase();
        
        tier.name = _name;
        tier.price = _price;
        tier.available = _available;
        tier.maxPerPurchase = _maxPerPurchase;
        
        emit TicketTierUpdated(_tierId, _name, _price, _available);
    }
    
    /* ========== TICKET PURCHASING ========== */
    
    /**
     * @notice Purchases tickets from specified tier
     * @dev Supports both Algorithm 1 (escrow) and Original (immediate payment) modes.
     *      Uses reentrancy guard and validates all purchase parameters.
     * @param _tierId ID of the ticket tier to purchase from
     * @param _quantity Number of tickets to purchase
     * @custom:security Protected by nonReentrant modifier and comprehensive validation
     * @custom:algorithm-one Funds held in escrow until event completion
     * @custom:original-algorithm Immediate payment to organizer after platform fee
     * @custom:events Emits TicketPurchased event
     * @custom:requirements Event must be active and not started yet
     */
    function purchaseTicket(uint256 _tierId, uint256 _quantity) external override nonReentrant eventActive {
        require(block.timestamp < date, "Event has already started");
        if(_tierId >= tierCount) revert TierDoesNotExist();
        Structs.TicketTier storage tier = ticketTiers[_tierId];
        
        // Validate purchase request against tier constraints
        if(!TicketLib.validateTicketPurchase(tier, _quantity)) revert InvalidPurchaseRequest();
        
        uint256 totalPrice = tier.price * _quantity;
        
        if (useAlgorithm1) {
            // Algorithm 1: Escrow-based payment model
            if(!idrxToken.transferFrom(_msgSender(), address(this), totalPrice)) revert TokenTransferFailed();
            organizerEscrow[organizer] += totalPrice;
            
            // Mint NFT tickets with deterministic Algorithm 1 token IDs
            for (uint256 i = 0; i < _quantity; i++) {
                uint256 tokenId = generateTokenId(eventId, _tierId, tier.sold + i + 1);
                ticketNFT.mintTicket(_msgSender(), tokenId, _tierId, tier.price);
                ticketExists[tokenId] = true;
            }
        } else {
            // Original algorithm: Immediate payment model
            if(!idrxToken.transferFrom(_msgSender(), address(this), totalPrice)) revert TokenTransferFailed();
            
            // Calculate and distribute platform fee
            uint256 platformFee = (totalPrice * Constants.PLATFORM_FEE_PERCENTAGE) / Constants.BASIS_POINTS;
            if(!idrxToken.transfer(platformFeeReceiver, platformFee)) revert PlatformFeeTransferFailed();
            
            // Transfer organizer share immediately
            uint256 organizerShare = totalPrice - platformFee;
            if(!idrxToken.transfer(organizer, organizerShare)) revert OrganizerPaymentFailed();
            
            // Mint NFT tickets with sequential token IDs
            for (uint256 i = 0; i < _quantity; i++) {
                ticketNFT.mintTicket(_msgSender(), _tierId, tier.price);
            }
        }
        
        // Update sold count for tier
        tier.sold += _quantity;
        
        emit TicketPurchased(_msgSender(), _tierId, _quantity);
    }
    
    /* ========== RESALE MARKETPLACE ========== */
    
    /**
     * @notice Configures resale marketplace rules for the event
     * @dev Sets maximum markup, organizer fees, and timing restrictions
     * @param _maxMarkupPercentage Maximum markup percentage in basis points (e.g., 500 = 5%)
     * @param _organizerFeePercentage Organizer fee percentage in basis points (e.g., 250 = 2.5%)
     * @param _restrictResellTiming Whether to enforce timing restrictions on resales
     * @param _minDaysBeforeEvent Minimum days before event for resale cutoff
     * @custom:security Maximum markup capped at 50%, organizer fee capped at 10%
     * @custom:events Emits ResaleRulesUpdated event
     */
    function setResaleRules(
        uint256 _maxMarkupPercentage,
        uint256 _organizerFeePercentage,
        bool _restrictResellTiming,
        uint256 _minDaysBeforeEvent
    ) external override onlyOrganizer {
        if(_maxMarkupPercentage > 5000) revert MaxMarkupExceeded(); // 50% = 5000 basis points
        if(_organizerFeePercentage > 1000) revert OrganizerFeeExceeded(); // 10% = 1000 basis points
        
        resaleRules.maxMarkupPercentage = _maxMarkupPercentage;
        resaleRules.organizerFeePercentage = _organizerFeePercentage;
        resaleRules.restrictResellTiming = _restrictResellTiming;
        resaleRules.minDaysBeforeEvent = _minDaysBeforeEvent;
        
        emit ResaleRulesUpdated(_maxMarkupPercentage, _organizerFeePercentage);
    }
    
    // List ticket for resale
    function listTicketForResale(uint256 _tokenId, uint256 _price) external override nonReentrant eventActive {
        if(!resaleRules.allowResell) revert ResaleNotAllowed();
        if(ticketNFT.ownerOf(_tokenId) != msg.sender) revert NotTicketOwner();
        
        // Get original price from metadata
        Structs.TicketMetadata memory metadata = ticketNFT.getTicketMetadata(_tokenId);
        if(metadata.used) revert TicketUsed();
        
        // Additional check for Algorithm 1 ticket status
        if (useAlgorithm1) {
            string memory status = ticketNFT.getTicketStatus(_tokenId);
            if (keccak256(bytes(status)) != keccak256(bytes("valid"))) {
                revert TicketUsed(); // Reuse existing error for consistency
            }
        }
        
        // Validate resale price
        if(!TicketLib.validateResalePrice(metadata.originalPrice, _price, resaleRules.maxMarkupPercentage))
            revert PriceExceedsMaxAllowed();
        
        // Check timing restrictions if enabled
        if (resaleRules.restrictResellTiming) {
            if(block.timestamp > date - (resaleRules.minDaysBeforeEvent * 1 days))
                revert TooCloseToEventDate();
        }
        
        // Transfer ticket to contract
        ticketNFT.transferFrom(msg.sender, address(this), _tokenId);
        
        // Create listing
        listings[_tokenId] = Structs.ListingInfo({
            seller: msg.sender,
            price: _price,
            active: true,
            listingDate: block.timestamp
        });
        
        emit TicketListedForResale(_tokenId, _price);
    }
    
    // Buy resale ticket
    function purchaseResaleTicket(uint256 _tokenId) external override nonReentrant eventActive {
        Structs.ListingInfo storage listing = listings[_tokenId];
        if(!listing.active) revert TicketNotListedForResale();
        
        // Calculate fees
        (uint256 organizerFee, uint256 platformFee) = TicketLib.calculateFees(
            listing.price,
            resaleRules.organizerFeePercentage,
            Constants.PLATFORM_FEE_PERCENTAGE
        );
        
        // Calculate seller amount
        uint256 sellerAmount = listing.price - organizerFee - platformFee;
        
        // Transfer tokens from buyer
        if(!idrxToken.transferFrom(msg.sender, address(this), listing.price)) revert PaymentFailed();
        
        // Transfer fees
        if(!idrxToken.transfer(organizer, organizerFee)) revert OrganizerFeeTransferFailed();
        if(!idrxToken.transfer(platformFeeReceiver, platformFee)) revert PlatformFeeTransferFailed();
        
        // Transfer seller amount
        if(!idrxToken.transfer(listing.seller, sellerAmount)) revert SellerPaymentFailed();
        
        // Transfer ticket to buyer
        ticketNFT.safeTransferFrom(address(this), msg.sender, _tokenId);
        
        // Mark ticket as transferred
        ticketNFT.markTransferred(_tokenId);
        
        // Clear listing
        delete listings[_tokenId];
        
        emit TicketResold(_tokenId, listing.seller, msg.sender, listing.price);
    }
    
    // Cancel a resale listing
    function cancelResaleListing(uint256 _tokenId) external nonReentrant {
        Structs.ListingInfo storage listing = listings[_tokenId];
        if(!listing.active) revert TicketNotListedForResale();
        if(listing.seller != msg.sender) revert NotSeller();
        
        // Transfer ticket back to seller
        ticketNFT.safeTransferFrom(address(this), msg.sender, _tokenId);
        
        // Clear listing
        delete listings[_tokenId];
        
        emit ResaleListingCancelled(_tokenId, msg.sender);
    }
    
    /* ========== STAFF MANAGEMENT ========== */
    
    /**
     * @notice Assigns a role to a staff member with hierarchical access control
     * @dev Only MANAGER role can assign staff. Only organizer can assign MANAGER role.
     * @param staff Address of the staff member to assign role to
     * @param role Role to assign from StaffRole enum (SCANNER, CHECKIN, MANAGER)
     * @custom:security Prevents privilege escalation - only organizer can create MANAGERs
     * @custom:compatibility Maintains legacy staffWhitelist for backward compatibility
     * @custom:events Emits StaffRoleAssigned event
     */
    function addStaffWithRole(address staff, StaffRole role) external onlyStaffRole(StaffRole.MANAGER) {
        require(staff != address(0), "Invalid staff address");
        require(role != StaffRole.NONE, "Cannot assign NONE role");
        
        // Prevent privilege escalation: only organizer can assign MANAGER role
        if (role == StaffRole.MANAGER && _msgSender() != organizer) {
            revert("Only organizer can assign MANAGER role");
        }
        
        staffRoles[staff] = role;
        staffWhitelist[staff] = true; // Maintain legacy compatibility
        
        emit StaffRoleAssigned(staff, role, _msgSender());
    }
    
    /**
     * @notice Removes a staff member's role and access privileges
     * @dev Only MANAGER role can remove staff. Only organizer can remove MANAGER role.
     * @param staff Address of the staff member to remove
     * @custom:security Prevents privilege escalation - only organizer can remove MANAGERs
     * @custom:protection Organizer cannot be removed from staff list
     * @custom:events Emits StaffRoleRemoved event
     */
    function removeStaffRole(address staff) external onlyStaffRole(StaffRole.MANAGER) {
        require(staff != organizer, "Cannot remove organizer");
        require(staffRoles[staff] != StaffRole.NONE, "Staff has no role");
        
        // Prevent privilege escalation: only organizer can remove MANAGER role
        if (staffRoles[staff] == StaffRole.MANAGER && _msgSender() != organizer) {
            revert("Only organizer can remove MANAGER role");
        }
        
        staffRoles[staff] = StaffRole.NONE;
        staffWhitelist[staff] = false; // Update legacy compatibility
        
        emit StaffRoleRemoved(staff, _msgSender());
    }
    
    /**
     * @notice Legacy function to add staff with default SCANNER role
     * @dev Maintained for backward compatibility. New code should use addStaffWithRole()
     * @param staff Address of the staff member to add
     * @custom:legacy This function assigns SCANNER role by default
     * @custom:events Emits StaffAdded event
     */
    function addStaff(address staff) external onlyOrganizer {
        require(staff != address(0), "Invalid staff address");
        staffWhitelist[staff] = true;
        staffRoles[staff] = StaffRole.SCANNER; // Default role
        emit StaffAdded(staff, _msgSender());
    }
    
    /**
     * @notice Legacy function to remove staff member
     * @dev Maintained for backward compatibility. New code should use removeStaffRole()
     * @param staff Address of the staff member to remove
     * @custom:legacy This function removes all roles and whitelist access
     * @custom:events Emits StaffRemoved event
     */
    function removeStaff(address staff) external onlyOrganizer {
        require(staff != organizer, "Cannot remove organizer");
        staffWhitelist[staff] = false;
        staffRoles[staff] = StaffRole.NONE;
        emit StaffRemoved(staff, _msgSender());
    }
    
    /**
     * @notice Updates ticket status from valid to used (Algorithm 1 only)
     * @dev Requires minimum SCANNER role. Updates NFT status to prevent reuse.
     * @param tokenId Token ID of the ticket to mark as used
     * @custom:algorithm-one Only available for events using Algorithm 1
     * @custom:security Requires SCANNER role or higher to prevent unauthorized scanning
     * @custom:validation Ensures ticket exists and is in valid state before updating
     * @custom:events Emits TicketStatusUpdated event
     */
    function updateTicketStatus(uint256 tokenId) external onlyStaffRole(StaffRole.SCANNER) nonReentrant {
        require(useAlgorithm1, "Only for Algorithm 1");
        require(ticketExists[tokenId], "Ticket does not exist");
        
        string memory currentStatus = ticketNFT.getTicketStatus(tokenId);
        require(keccak256(bytes(currentStatus)) == keccak256(bytes("valid")), "Ticket not valid");
        
        // Update status from "valid" to "used"
        ticketNFT.updateStatus(tokenId, "used");
        
        emit TicketStatusUpdated(tokenId, "valid", "used");
    }
    
    /* ========== ALGORITHM 1 FUNCTIONS ========== */
    
    /**
     * @notice Generates deterministic token ID for Algorithm 1 tickets
     * @dev Creates unique token ID using event ID, tier, and sequential number
     * @param _eventId Unique event identifier (0-999)
     * @param tierCode Ticket tier identifier (0-9)
     * @param sequential Sequential number within tier (1-99999)
     * @return tokenId Deterministic token ID in format: 1EEETTSSSS
     *                 where EEE=eventId, TT=tier+1, SSSS=sequential
     * @custom:format Token ID format ensures uniqueness across all events
     */
    function generateTokenId(
        uint256 _eventId,
        uint256 tierCode,
        uint256 sequential
    ) internal pure returns (uint256) {
        require(_eventId <= 999, "Event ID too large");
        require(tierCode <= 9, "Tier code too large");
        require(sequential <= 99999, "Sequential number too large");
        
        // Convert tier 0 to tier 1 for token ID format
        uint256 actualTierCode = tierCode + 1;
        
        return (1 * 1e9) + (_eventId * 1e6) + (actualTierCode * 1e5) + sequential;
    }
    
    /**
     * @notice Sets the algorithm mode for the event
     * @dev Only factory can call. Locked once algorithm is locked by organizer.
     * @param _useAlgorithm1 True for Algorithm 1 (escrow), false for Original
     * @param _eventId Event ID for Algorithm 1 (ignored for Original)
     * @custom:security Only factory can set algorithm, only when not locked
     * @custom:algorithm-one Event ID is required for Algorithm 1 token generation
     */
    function setAlgorithm1(bool _useAlgorithm1, uint256 _eventId) external algorithmNotLocked {
        require(msg.sender == factory, "Only factory can set algorithm");
        useAlgorithm1 = _useAlgorithm1;
        if (_useAlgorithm1) {
            eventId = _eventId;
        }
    }
    
    /**
     * @notice Permanently locks the algorithm to prevent mid-event changes
     * @dev Once locked, algorithm cannot be changed for security reasons
     * @custom:security Prevents malicious algorithm switching during active events
     * @custom:events Emits AlgorithmLocked event
     */
    function lockAlgorithm() external onlyOrganizer {
        algorithmLocked = true;
        emit AlgorithmLocked();
    }
    
    /* ========== EVENT LIFECYCLE MANAGEMENT ========== */
    
    /**
     * @notice Cancels the event and processes automatic refunds
     * @dev Automatically refunds all valid tickets when event is cancelled.
     *      Can only be called before event start date.
     * @custom:security Only organizer can cancel, only before event starts
     * @custom:refunds Automatically processes refunds for all valid tickets
     * @custom:algorithm-one Algorithm 1 tickets are auto-refunded from escrow
     * @custom:events Emits EventCancelled and RefundProcessed events
     */
    function cancelEvent() external override onlyOrganizer {
        if(cancelled) revert EventAlreadyCancelled();
        if(block.timestamp >= date) revert EventNotStarted();
        
        cancelled = true;
        
        // Process automatic refunds for all tickets
        _processAllRefunds();
        
        emit EventCancelled();
    }
    
    /**
     * @dev Internal function to process automatic refunds for all tickets
     *      Iterates through all sold tickets and refunds valid ones
     * @custom:algorithm-one Processes refunds from escrow for Algorithm 1 tickets
     * @custom:original-algorithm Users must claim refunds manually via emergencyRefund
     * @custom:gas-optimization Uses try-catch to handle non-existent tokens gracefully
     */
    function _processAllRefunds() internal {
        // Iterate through all tiers and process refunds
        for (uint256 tierId = 0; tierId < tierCount; tierId++) {
            Structs.TicketTier storage tier = ticketTiers[tierId];
            
            // Process refunds for all sold tickets in this tier
            for (uint256 ticketIndex = 1; ticketIndex <= tier.sold; ticketIndex++) {
                if (useAlgorithm1) {
                    uint256 tokenId = generateTokenId(eventId, tierId, ticketIndex);
                    
                    // Safely check token existence and process refund
                    try ticketNFT.ownerOf(tokenId) returns (address owner) {
                        string memory status = ticketNFT.getTicketStatus(tokenId);
                        if (keccak256(bytes(status)) == keccak256(bytes("valid"))) {
                            uint256 refundAmount = tier.price;
                            
                            // Process refund from escrow
                            if (idrxToken.balanceOf(address(this)) >= refundAmount) {
                                idrxToken.transfer(owner, refundAmount);
                                ticketNFT.updateStatus(tokenId, "refunded");
                                emit RefundProcessed(owner, refundAmount);
                            }
                        }
                    } catch {
                        // Token doesn't exist or error accessing it, skip
                        continue;
                    }
                } else {
                    // Original algorithm: Users must claim refunds manually
                    // via emergencyRefund function due to non-deterministic token IDs
                    continue;
                }
            }
        }
    }
    
    /**
     * @notice Processes refund for a specific user (called by NFT contract)
     * @dev Only TicketNFT contract can call this function for Algorithm 1 refunds
     * @param to Address to receive the refund
     * @param amount Amount to refund in IDRX tokens
     * @custom:algorithm-one Transfers from contract escrow, not organizer balance
     * @custom:security Only NFT contract can call, only when event is cancelled
     * @custom:events Emits RefundProcessed event
     */
    function processRefund(address to, uint256 amount) external {
        require(msg.sender == address(ticketNFT), "Only NFT contract can process refund");
        require(cancelled, "Event not cancelled");
        
        // Transfer from contract escrow
        bool success = idrxToken.transfer(to, amount);
        require(success, "Token transfer failed");
        
        emit RefundProcessed(to, amount);
    }
    
    /**
     * @notice Marks the event as completed after it has finished
     * @dev Allows organizer fund withdrawal. Requires 1-day grace period after event.
     * @custom:timing Requires event date + 1 day grace period to have passed
     * @custom:security Cannot complete cancelled events
     * @custom:funds Enables organizer to withdraw escrowed funds
     * @custom:events Emits EventCompleted event
     */
    function markEventCompleted() external onlyOrganizer {
        require(block.timestamp >= date + 1 days, "Event not yet completed"); // 1 day grace period
        require(!cancelled, "Cannot complete cancelled event");
        
        eventCompleted = true;
        
        emit EventCompleted();
    }
    
    /**
     * @notice Allows organizer to withdraw escrowed funds after event completion
     * @dev Only available after event is marked complete and not cancelled.
     *      Uses reentrancy guard and follows checks-effects-interactions pattern.
     * @custom:algorithm-one Withdraws from escrow (Algorithm 1 only)
     * @custom:security Protected by nonReentrant modifier
     * @custom:requirements Event must be completed and not cancelled
     * @custom:events Emits OrganizerFundsWithdrawn event
     */
    function withdrawOrganizerFunds() external onlyOrganizer nonReentrant {
        require(eventCompleted, "Event not completed yet");
        require(!cancelled, "Cannot withdraw from cancelled event");
        
        uint256 amount = organizerEscrow[organizer];
        if(amount == 0) revert NoFundsToWithdraw();
        
        // Clear escrow before transfer (checks-effects-interactions)
        organizerEscrow[organizer] = 0;
        
        if(!idrxToken.transfer(organizer, amount)) revert WithdrawFailed();
        
        emit OrganizerFundsWithdrawn(organizer, amount);
    }
    
    /**
     * @notice Emergency refund for individual ticket owners when event is cancelled
     * @dev Allows users to claim refunds for their tickets when auto-refund fails.
     *      Protected by reentrancy guard.
     * @param tokenId Token ID of the ticket to refund
     * @custom:emergency For cases where automatic refund processing fails
     * @custom:algorithm-one Updates ticket status to "refunded"
     * @custom:original-algorithm Checks ticket not used via metadata
     * @custom:security Only ticket owner can claim, only when event cancelled
     * @custom:events Emits RefundProcessed event
     */
    function emergencyRefund(uint256 tokenId) external nonReentrant {
        require(cancelled, "Event not cancelled");
        require(ticketNFT.ownerOf(tokenId) == _msgSender(), "Not token owner");
        
        // Get ticket metadata for refund amount
        Structs.TicketMetadata memory metadata = ticketNFT.getTicketMetadata(tokenId);
        
        // Algorithm-specific validation
        if (useAlgorithm1) {
            string memory status = ticketNFT.getTicketStatus(tokenId);
            require(keccak256(bytes(status)) == keccak256(bytes("valid")), "Ticket not eligible for refund");
            ticketNFT.updateStatus(tokenId, "refunded");
        } else {
            require(!metadata.used, "Ticket already used");
        }
        
        uint256 refundAmount = metadata.originalPrice;
        
        // Transfer refund to ticket owner
        if(!idrxToken.transfer(_msgSender(), refundAmount)) revert TokenTransferFailed();
        
        emit RefundProcessed(_msgSender(), refundAmount);
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    /**
     * @notice Returns the address of the associated TicketNFT contract
     * @return Address of the TicketNFT contract for this event
     */
    function getTicketNFT() external view override returns (address) {
        return address(ticketNFT);
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
    
    /**
     * @notice Checks if an address is in the staff whitelist (legacy function)
     * @param account Address to check
     * @return bool True if address is whitelisted staff
     * @custom:legacy Use getStaffRole() for role-based access control
     */
    function isStaff(address account) external view returns (bool) {
        return staffWhitelist[account];
    }
    
    /**
     * @notice Gets the staff role assigned to an address
     * @param account Address to check
     * @return StaffRole The role assigned to the address (NONE, SCANNER, CHECKIN, MANAGER)
     */
    function getStaffRole(address account) external view returns (StaffRole) {
        return staffRoles[account];
    }
    
    /**
     * @notice Checks if an address has sufficient privileges for a required role
     * @param account Address to check
     * @param requiredRole Minimum role required
     * @return bool True if address has sufficient privileges
     * @custom:hierarchy Higher roles inherit permissions from lower roles
     */
    function hasStaffRole(address account, StaffRole requiredRole) external view returns (bool) {
        return staffRoles[account] >= requiredRole;
    }
    
    /* ========== EVENTS ========== */
    
    /// @notice Emitted when a new ticket tier is created
    event TicketTierAdded(uint256 indexed tierId, string name, uint256 price);
    
    /// @notice Emitted when a ticket tier is updated
    event TicketTierUpdated(uint256 indexed tierId, string name, uint256 price, uint256 available);
    
    /// @notice Emitted when tickets are purchased
    event TicketPurchased(address indexed buyer, uint256 indexed tierId, uint256 quantity);
    
    /// @notice Emitted when resale rules are updated
    event ResaleRulesUpdated(uint256 maxMarkupPercentage, uint256 organizerFeePercentage);
    
    /// @notice Emitted when a ticket is listed for resale
    event TicketListedForResale(uint256 indexed tokenId, uint256 price);
    
    /// @notice Emitted when a ticket is sold in the resale marketplace
    event TicketResold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    
    /// @notice Emitted when a resale listing is cancelled
    event ResaleListingCancelled(uint256 indexed tokenId, address indexed seller);
    
    /// @notice Emitted when the event is cancelled
    event EventCancelled();
    
    /// @notice Emitted when the event is marked as completed
    event EventCompleted();
    
    /// @notice Emitted when organizer withdraws escrowed funds
    event OrganizerFundsWithdrawn(address indexed organizer, uint256 amount);
    
    // Staff management events
    /// @notice Emitted when staff is added (legacy function)
    event StaffAdded(address indexed staff, address indexed organizer);
    
    /// @notice Emitted when staff is removed (legacy function)
    event StaffRemoved(address indexed staff, address indexed organizer);
    
    /// @notice Emitted when a staff role is assigned
    event StaffRoleAssigned(address indexed staff, StaffRole role, address indexed assignedBy);
    
    /// @notice Emitted when a staff role is removed
    event StaffRoleRemoved(address indexed staff, address indexed removedBy);
    
    // Algorithm management events
    /// @notice Emitted when algorithm is permanently locked
    event AlgorithmLocked();
    
    // Algorithm 1 specific events
    /// @notice Emitted when ticket status is updated (Algorithm 1)
    event TicketStatusUpdated(uint256 indexed tokenId, string oldStatus, string newStatus);
    
    /// @notice Emitted when a refund is processed
    event RefundProcessed(address indexed to, uint256 amount);
}