// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {LibAppStorage} from "src/diamond/LibAppStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/utils/Context.sol";
import "src/libraries/Structs.sol";
import "src/libraries/Constants.sol";
import "src/libraries/TicketLib.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import "src/interfaces/ITicketNFT.sol";

/// @title MarketplaceFacet - Resale marketplace functionality facet
/// @author Lummy Protocol Team
/// @notice Handles ticket resale, listing, and P2P trading operations
/// @dev Part of Diamond pattern implementation - ~19KB target size
contract MarketplaceFacet is ReentrancyGuard, ERC2771Context {
    using LibAppStorage for LibAppStorage.AppStorage;

    /// @notice Custom errors for gas efficiency
    error EventIsCancelled();
    error ResaleNotAllowed();
    error NotTicketOwner();
    error TicketUsed();
    error PriceExceedsMaxAllowed();
    error TooCloseToEventDate();
    error TicketNotListedForResale();
    error PaymentFailed();
    error OrganizerFeeTransferFailed();
    error PlatformFeeTransferFailed();
    error SellerPaymentFailed();
    error NotSeller();

    /// @notice Constructor for ERC2771 context
    /// @param trustedForwarder Address of trusted forwarder for gasless transactions
    constructor(address trustedForwarder) ERC2771Context(trustedForwarder) {}

    /// @notice Lists a ticket for resale on the marketplace
    /// @param _tokenId Token ID of the ticket to list
    /// @param _price Price to list the ticket for (in IDRX tokens)
    function listTicketForResale(uint256 _tokenId, uint256 _price) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (s.cancelled) revert EventIsCancelled();
        if (!s.resaleRules.allowResell) revert ResaleNotAllowed();
        if (s.ticketNFT.ownerOf(_tokenId) != _msgSender()) revert NotTicketOwner();
        
        // Get original price from metadata
        Structs.TicketMetadata memory metadata = s.ticketNFT.getTicketMetadata(_tokenId);
        if (metadata.used) revert TicketUsed();
        
        // Additional check for Algorithm 1 ticket status
        if (s.useAlgorithm1) {
            string memory status = s.ticketNFT.getTicketStatus(_tokenId);
            if (keccak256(bytes(status)) != keccak256(bytes("valid"))) {
                revert TicketUsed();
            }
        }
        
        // Validate resale price against markup limits
        if (!TicketLib.validateResalePrice(metadata.originalPrice, _price, s.resaleRules.maxMarkupPercentage)) {
            revert PriceExceedsMaxAllowed();
        }
        
        // Check timing restrictions if enabled
        if (s.resaleRules.restrictResellTiming) {
            if (block.timestamp > s.date - (s.resaleRules.minDaysBeforeEvent * 1 days)) {
                revert TooCloseToEventDate();
            }
        }
        
        // Transfer ticket to contract for escrow
        s.ticketNFT.transferFrom(_msgSender(), address(this), _tokenId);
        
        // Create listing
        s.listings[_tokenId] = Structs.ListingInfo({
            seller: _msgSender(),
            price: _price,
            active: true,
            listingDate: block.timestamp
        });
        
        emit TicketListedForResale(_tokenId, _msgSender(), _price);
    }

    /// @notice Purchases a ticket from the resale marketplace
    /// @param _tokenId Token ID of the ticket to purchase
    function purchaseResaleTicket(uint256 _tokenId) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (s.cancelled) revert EventIsCancelled();
        
        Structs.ListingInfo storage listing = s.listings[_tokenId];
        if (!listing.active) revert TicketNotListedForResale();
        
        // Calculate fees using library function
        (uint256 organizerFee, uint256 platformFee) = TicketLib.calculateFees(
            listing.price,
            s.resaleRules.organizerFeePercentage,
            Constants.PLATFORM_FEE_PERCENTAGE
        );
        
        // Calculate seller amount
        uint256 sellerAmount = listing.price - organizerFee - platformFee;
        
        // Transfer tokens from buyer
        if (!s.idrxToken.transferFrom(_msgSender(), address(this), listing.price)) {
            revert PaymentFailed();
        }
        
        // Transfer fees to respective parties
        if (!s.idrxToken.transfer(s.organizer, organizerFee)) {
            revert OrganizerFeeTransferFailed();
        }
        if (!s.idrxToken.transfer(s.platformFeeReceiver, platformFee)) {
            revert PlatformFeeTransferFailed();
        }
        
        // Transfer seller amount
        if (!s.idrxToken.transfer(listing.seller, sellerAmount)) {
            revert SellerPaymentFailed();
        }
        
        // Transfer ticket to buyer
        s.ticketNFT.safeTransferFrom(address(this), _msgSender(), _tokenId);
        
        // Mark ticket as transferred to track secondary market activity
        s.ticketNFT.markTransferred(_tokenId);
        
        // Update analytics
        s.tokenResaleCount[_tokenId]++;
        s.userResaleRevenue[listing.seller] += sellerAmount;
        s.totalMarketplaceVolume += listing.price;
        
        address seller = listing.seller;
        uint256 price = listing.price;
        
        // Clear listing
        delete s.listings[_tokenId];
        
        emit TicketResold(_tokenId, seller, _msgSender(), price);
    }

    /// @notice Cancels a resale listing and returns ticket to seller
    /// @param _tokenId Token ID of the listing to cancel
    function cancelResaleListing(uint256 _tokenId) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        Structs.ListingInfo storage listing = s.listings[_tokenId];
        if (!listing.active) revert TicketNotListedForResale();
        if (listing.seller != _msgSender()) revert NotSeller();
        
        // Transfer ticket back to seller
        s.ticketNFT.safeTransferFrom(address(this), _msgSender(), _tokenId);
        
        // Clear listing
        delete s.listings[_tokenId];
        
        emit ResaleListingCancelled(_tokenId, _msgSender());
    }

    /// @notice Updates resale rules for the event (organizer only)
    /// @param _allowResell Whether to allow ticket resales
    /// @param _requireVerification Whether to require identity verification for resales
    function updateResaleSettings(bool _allowResell, bool _requireVerification) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        require(_msgSender() == s.organizer, "Only organizer can update resale settings");
        
        s.resaleRules.allowResell = _allowResell;
        s.resaleRules.requireVerification = _requireVerification;
        
        emit ResaleSettingsUpdated(_allowResell, _requireVerification);
    }

    /// @notice Gets listing information for a token
    /// @param tokenId Token ID to query
    /// @return Listing information struct
    function getListing(uint256 tokenId) external view returns (Structs.ListingInfo memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.listings[tokenId];
    }

    /// @notice Checks if a ticket is currently listed for resale
    /// @param tokenId Token ID to check
    /// @return True if ticket is actively listed
    function isListedForResale(uint256 tokenId) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.listings[tokenId].active;
    }

    /// @notice Gets all active listings (for frontend display)
    /// @dev This function may be gas-intensive for large numbers of listings
    /// @return tokenIds Array of token IDs that are listed
    /// @return prices Array of listing prices
    /// @return sellers Array of seller addresses
    function getActiveListings() external view returns (
        uint256[] memory tokenIds,
        uint256[] memory prices,
        address[] memory sellers
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // First pass: count active listings
        uint256 activeCount = 0;
        // Note: This is a simplified implementation. In production, you'd want to maintain
        // a separate array of active listings to avoid iterating through all possible token IDs
        
        // For this implementation, we'll return empty arrays and recommend
        // using events to track active listings in the frontend
        tokenIds = new uint256[](0);
        prices = new uint256[](0);
        sellers = new address[](0);
    }

    /// @notice Gets marketplace analytics for a token
    /// @param tokenId Token ID to query
    /// @return resaleCount Number of times token has been resold
    function getTokenMarketplaceStats(uint256 tokenId) external view returns (uint256 resaleCount) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.tokenResaleCount[tokenId];
    }

    /// @notice Gets user's resale revenue statistics
    /// @param user Address to query
    /// @return totalRevenue Total revenue earned from resales
    function getUserResaleRevenue(address user) external view returns (uint256 totalRevenue) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.userResaleRevenue[user];
    }

    /// @notice Gets total marketplace volume
    /// @return Total volume of all marketplace transactions
    function getTotalMarketplaceVolume() external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.totalMarketplaceVolume;
    }

    /// @notice Calculates the maximum allowed resale price for a ticket
    /// @param originalPrice Original ticket price
    /// @return Maximum allowed resale price
    function getMaxResalePrice(uint256 originalPrice) external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return originalPrice + (originalPrice * s.resaleRules.maxMarkupPercentage / Constants.BASIS_POINTS);
    }

    /// @notice Calculates fees for a resale transaction
    /// @param resalePrice Price of the resale ticket
    /// @return organizerFee Fee paid to event organizer
    /// @return platformFee Fee paid to platform
    /// @return sellerAmount Amount paid to seller
    function calculateResaleFees(uint256 resalePrice) external view returns (
        uint256 organizerFee,
        uint256 platformFee,
        uint256 sellerAmount
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        (organizerFee, platformFee) = TicketLib.calculateFees(
            resalePrice,
            s.resaleRules.organizerFeePercentage,
            Constants.PLATFORM_FEE_PERCENTAGE
        );
        
        sellerAmount = resalePrice - organizerFee - platformFee;
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
    event TicketListedForResale(uint256 indexed tokenId, address indexed seller, uint256 price);
    event TicketResold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event ResaleListingCancelled(uint256 indexed tokenId, address indexed seller);
    event ResaleSettingsUpdated(bool allowResell, bool requireVerification);
}