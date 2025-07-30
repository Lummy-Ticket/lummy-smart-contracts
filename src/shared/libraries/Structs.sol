// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

library Structs {
    // Detail event
    struct EventDetails {
        string name;
        string description;
        uint256 date;
        string venue;
        string ipfsMetadata;
        address organizer;
    }
    
    // Tier tiket
    struct TicketTier {
        string name;
        uint256 price;
        uint256 available;
        uint256 sold;
        uint256 maxPerPurchase;
        bool active;
    }
    
    // Aturan resale
    struct ResaleRules {
        bool allowResell;
        uint256 maxMarkupPercentage;
        uint256 organizerFeePercentage;
        bool restrictResellTiming;
        uint256 minDaysBeforeEvent;
        bool requireVerification;
    }
    
    // Enhanced metadata tiket with OpenSea traits
    struct TicketMetadata {
        // Core metadata
        uint256 eventId;
        uint256 tierId;
        uint256 originalPrice;
        bool used;
        uint256 purchaseDate;
        
        // Enhanced metadata for OpenSea traits
        string eventName;         // Event name for display
        string eventVenue;        // Event venue
        uint256 eventDate;        // Event date timestamp
        string tierName;          // Tier name (VIP, Regular, etc.)
        string organizerName;     // Organizer name
        uint256 serialNumber;     // Serial number within tier (for rarity)
        string status;            // Current status ("valid", "used", "refunded")
        uint256 transferCount;    // Number of times transferred
    }
    
    // Informasi listing marketplace
    struct ListingInfo {
        address seller;
        uint256 price;
        bool active;
        uint256 listingDate;
    }
}