// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import "src/shared/libraries/Structs.sol";
import "src/shared/interfaces/ITicketNFT.sol";

/// @title LibAppStorage - Application storage library for Diamond pattern
/// @author Lummy Protocol Team
/// @notice Defines the shared application storage layout for all facets
/// @dev Uses AppStorage pattern to prevent storage collisions between facets
library LibAppStorage {
    /// @notice Application storage position to avoid collisions
    bytes32 constant APP_STORAGE_POSITION = keccak256("lummy.app.storage");

    /// @notice Staff role enumeration for hierarchical access control
    enum StaffRole { 
        NONE,       // No staff privileges
        SCANNER,    // Can scan/validate tickets
        CHECKIN,    // Can check-in attendees + SCANNER privileges
        MANAGER     // Can manage staff + CHECKIN privileges
    }

    /// @notice Main application storage struct containing all shared state
    struct AppStorage {
        // ========== EVENT CORE INFORMATION ==========
        /// @notice Basic event information
        string name;
        string description;
        uint256 date;
        string venue;
        string ipfsMetadata;
        string category;        // Event category: "Music", "Sports", "Technology", dll
        address organizer;
        
        /// @notice Event status flags
        bool cancelled;
        bool eventCompleted;
        
        /// @notice Factory and platform addresses
        address factory;
        address platformFeeReceiver;
        
        // ========== ALGORITHM CONFIGURATION ==========
        /// @notice Algorithm configuration (standardized to Algorithm 1)
        uint256 eventId;                    // Unique ID for deterministic token generation
        
        // ========== CONTRACT REFERENCES ==========
        /// @notice Contract references
        ITicketNFT ticketNFT;               // NFT contract for tickets
        IERC20 idrxToken;                   // Payment token contract
        
        // ========== TICKET TIERS ==========
        /// @notice Ticket tier management
        mapping(uint256 => Structs.TicketTier) ticketTiers;
        uint256 tierCount;
        
        // ========== RESALE MARKETPLACE ==========
        /// @notice Resale marketplace configuration and data
        Structs.ResaleRules resaleRules;
        mapping(uint256 => Structs.ListingInfo) listings;
        
        // ========== STAFF MANAGEMENT ==========
        /// @notice Staff role management
        mapping(address => StaffRole) staffRoles;
        mapping(address => bool) staffWhitelist;    // Legacy compatibility
        
        // ========== ALGORITHM 1 SPECIFIC ==========
        /// @notice Algorithm 1 specific data
        mapping(uint256 => bool) ticketExists;      // Token ID existence tracking
        mapping(address => uint256) organizerEscrow; // Escrow funds for organizers
        
        // ========== PLATFORM FEES ==========
        /// @notice Platform fee collection and management
        uint256 platformFeesCollected;                  // Total platform fees collected
        uint256 platformFeesWithdrawn;                  // Total platform fees withdrawn
        
        // ========== ANALYTICS & STATISTICS ==========
        /// @notice Event analytics data (for future AnalyticsFacet)
        mapping(uint256 => uint256) tierSalesCount;     // Sales count per tier
        mapping(address => uint256) userPurchaseCount;  // Purchase count per user
        uint256 totalRevenue;                           // Total event revenue
        uint256 totalRefunds;                           // Total refunds processed
        
        // ========== GASLESS TRANSACTIONS ==========
        /// @notice Gasless transaction support
        address trustedForwarder;                       // ERC2771 forwarder
        mapping(address => uint256) nonces;             // User nonces for meta-tx
        
        // ========== ACCESS CONTROL ==========
        /// @notice Enhanced access control
        mapping(bytes32 => mapping(address => bool)) roles; // Role-based access
        mapping(bytes32 => bytes32) roleAdmin;               // Role admin mapping
        
        // ========== MARKETPLACE ANALYTICS ==========
        /// @notice Marketplace specific analytics
        mapping(uint256 => uint256) tokenResaleCount;   // Resale count per token
        mapping(address => uint256) userResaleRevenue;  // Revenue per user from resales
        uint256 totalMarketplaceVolume;                 // Total marketplace trading volume
        
        // ========== EVENT LIFECYCLE ==========
        /// @notice Event lifecycle tracking
        uint256 eventCreatedAt;                         // Event creation timestamp
        uint256 ticketSalesStartAt;                     // Ticket sales start time
        uint256 ticketSalesEndAt;                       // Ticket sales end time
        bool ticketSalesActive;                         // Ticket sales status
        
        // ========== RESERVED STORAGE ==========
        /// @notice Reserved storage slots for future upgrades (32 slots)
        uint256[32] __gap;
    }

    /// @notice Gets the application storage struct
    /// @return s The application storage struct
    function appStorage() internal pure returns (AppStorage storage s) {
        bytes32 position = APP_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    /// @notice Gets the current event organizer
    /// @return The organizer address
    function organizer() internal view returns (address) {
        return appStorage().organizer;
    }

    /// @notice Gets the factory contract address
    /// @return The factory address
    function factory() internal view returns (address) {
        return appStorage().factory;
    }

    /// @notice Checks if event is cancelled
    /// @return True if event is cancelled
    function isCancelled() internal view returns (bool) {
        return appStorage().cancelled;
    }

    /// @notice Checks if event is completed
    /// @return True if event is completed
    function isCompleted() internal view returns (bool) {
        return appStorage().eventCompleted;
    }


    /// @notice Gets staff role for an address
    /// @param account Address to check
    /// @return The staff role assigned to the address
    function getStaffRole(address account) internal view returns (StaffRole) {
        return appStorage().staffRoles[account];
    }

    /// @notice Checks if address has sufficient staff privileges
    /// @param account Address to check
    /// @param requiredRole Minimum required role
    /// @return True if account has sufficient privileges
    function hasStaffRole(address account, StaffRole requiredRole) internal view returns (bool) {
        return appStorage().staffRoles[account] >= requiredRole;
    }

    /// @notice Gets the event date
    /// @return Unix timestamp of event date
    function eventDate() internal view returns (uint256) {
        return appStorage().date;
    }

    /// @notice Gets the tier count
    /// @return Number of ticket tiers created
    function getTierCount() internal view returns (uint256) {
        return appStorage().tierCount;
    }

    /// @notice Gets ticket tier information
    /// @param tierId ID of the tier
    /// @return Ticket tier struct
    function getTicketTier(uint256 tierId) internal view returns (Structs.TicketTier storage) {
        return appStorage().ticketTiers[tierId];
    }

    /// @notice Gets resale rules
    /// @return Resale rules struct
    function getResaleRules() internal view returns (Structs.ResaleRules storage) {
        return appStorage().resaleRules;
    }

    /// @notice Gets listing information for a token
    /// @param tokenId Token ID to check
    /// @return Listing information struct
    function getListing(uint256 tokenId) internal view returns (Structs.ListingInfo storage) {
        return appStorage().listings[tokenId];
    }

    /// @notice Updates total revenue
    /// @param amount Amount to add to total revenue
    function addToTotalRevenue(uint256 amount) internal {
        appStorage().totalRevenue += amount;
    }

    /// @notice Updates total refunds
    /// @param amount Amount to add to total refunds
    function addToTotalRefunds(uint256 amount) internal {
        appStorage().totalRefunds += amount;
    }

    /// @notice Updates marketplace volume
    /// @param amount Amount to add to marketplace volume
    function addToMarketplaceVolume(uint256 amount) internal {
        appStorage().totalMarketplaceVolume += amount;
    }

    /// @notice Custom errors for access control
    error OnlyOrganizerCanCall();
    error OnlyFactoryCanCall();
    error InsufficientStaffPrivileges(address account, StaffRole required, StaffRole actual);
    error EventIsCancelled();
    error EventNotActive();

    /// @notice Modifier to restrict access to organizer only
    modifier onlyOrganizer() {
        if (msg.sender != appStorage().organizer) {
            revert OnlyOrganizerCanCall();
        }
        _;
    }

    /// @notice Modifier to restrict access to factory only
    modifier onlyFactory() {
        if (msg.sender != appStorage().factory) {
            revert OnlyFactoryCanCall();
        }
        _;
    }

    /// @notice Modifier to ensure event is not cancelled
    modifier eventActive() {
        if (appStorage().cancelled) {
            revert EventIsCancelled();
        }
        _;
    }

    /// @notice Modifier to check staff role requirements
    /// @param requiredRole Minimum role required
    modifier onlyStaffRole(StaffRole requiredRole) {
        StaffRole userRole = appStorage().staffRoles[msg.sender];
        if (userRole < requiredRole) {
            revert InsufficientStaffPrivileges(msg.sender, requiredRole, userRole);
        }
        _;
    }

}