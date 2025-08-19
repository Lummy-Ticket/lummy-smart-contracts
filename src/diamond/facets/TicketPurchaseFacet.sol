// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {LibAppStorage} from "src/diamond/LibAppStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/utils/Context.sol";
import "src/shared/libraries/Structs.sol";
import "src/shared/libraries/Constants.sol";
import "src/shared/libraries/TicketLib.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import "src/shared/interfaces/ITicketNFT.sol";

/// @title TicketPurchaseFacet - Ticket purchasing functionality facet
/// @author Lummy Protocol Team
/// @notice Handles ticket purchasing, refunds, and payment processing
/// @dev Part of Diamond pattern implementation - ~18KB target size
contract TicketPurchaseFacet is ReentrancyGuard, ERC2771Context {
    using LibAppStorage for LibAppStorage.AppStorage;

    /// @notice Custom errors for gas efficiency
    error EventIsCancelled();
    error TierDoesNotExist();
    error InvalidPurchaseRequest();
    error TokenTransferFailed();
    error PlatformFeeTransferFailed();
    error OrganizerPaymentFailed();
    error NoFundsToWithdraw();
    error WithdrawFailed();

    /// @notice Constructor for ERC2771 context
    /// @param trustedForwarder Address of trusted forwarder for gasless transactions
    constructor(address trustedForwarder) ERC2771Context(trustedForwarder) {}

    /// @notice Purchases tickets from specified tier
    /// @param _tierId ID of the ticket tier to purchase from
    /// @param _quantity Number of tickets to purchase
    function purchaseTicket(uint256 _tierId, uint256 _quantity) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (s.cancelled) revert EventIsCancelled();
        require(block.timestamp < s.date, "Event has already started");
        
        if (_tierId >= s.tierCount) revert TierDoesNotExist();
        Structs.TicketTier storage tier = s.ticketTiers[_tierId];
        
        // Validate purchase request against tier constraints
        if (!TicketLib.validateTicketPurchase(tier, _quantity)) revert InvalidPurchaseRequest();
        
        uint256 totalPrice = tier.price * _quantity;
        
        // Always use escrow model (Algorithm 1)
        _purchaseTicket(s, tier, _tierId, _quantity, totalPrice);
        
        // Update sold count and analytics
        tier.sold += _quantity;
        s.tierSalesCount[_tierId] += _quantity;
        s.userPurchaseCount[_msgSender()] += _quantity;
        s.totalRevenue += totalPrice;
        
        emit TicketPurchased(_msgSender(), _tierId, _quantity, totalPrice);
    }

    /// @notice Internal function for ticket purchases (escrow model)
    /// @param s App storage reference
    /// @param tier Ticket tier reference
    /// @param _tierId Tier ID
    /// @param _quantity Quantity to purchase
    /// @param totalPrice Total price for purchase
    function _purchaseTicket(
        LibAppStorage.AppStorage storage s,
        Structs.TicketTier storage tier,
        uint256 _tierId,
        uint256 _quantity,
        uint256 totalPrice
    ) internal {
        // Transfer tokens to contract escrow
        if (!s.idrxToken.transferFrom(_msgSender(), address(this), totalPrice)) {
            revert TokenTransferFailed();
        }
        
        // Calculate platform fee (7% of total price)
        uint256 platformFee = (totalPrice * Constants.PLATFORM_PRIMARY_FEE_PERCENTAGE) / Constants.BASIS_POINTS;
        uint256 escrowAmount = totalPrice - platformFee;
        
        // Add platform fee to collection
        s.platformFeesCollected += platformFee;
        
        // Add remaining amount to organizer escrow (93% of ticket price)
        s.organizerEscrow[s.organizer] += escrowAmount;
        
        // Cache values to avoid stack too deep error
        string memory eventName = s.name;
        string memory eventVenue = s.venue;
        uint256 eventDate = s.date;
        string memory organizerName = _addressToString(s.organizer);
        
        // Mint NFT tickets with deterministic Algorithm 1 token IDs
        for (uint256 i = 0; i < _quantity; i++) {
            uint256 tokenId = _generateTokenId(s.eventId, _tierId, tier.sold + i + 1);
            s.ticketNFT.mintTicket(_msgSender(), tokenId, _tierId, tier.price);
            
            // NEW: Auto-populate enhanced metadata immediately after minting
            s.ticketNFT.setEnhancedMetadata(
                tokenId,
                eventName,        // eventName
                eventVenue,       // eventVenue  
                eventDate,        // eventDate
                tier.name,        // tierName
                organizerName     // organizerName
            );
            
            // NEW: Phase 1.3 - Track attendee efficiently (replaces 5000+ contract call discovery)
            _trackNewAttendee(s, _msgSender(), tokenId);
            
            s.ticketExists[tokenId] = true;
        }
    }


    /// @notice Allows organizer to withdraw escrowed funds after event completion
    function withdrawOrganizerFunds() external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        require(_msgSender() == s.organizer, "Only organizer can withdraw");
        require(s.eventCompleted, "Event not completed yet");
        require(!s.cancelled, "Cannot withdraw from cancelled event");
        
        uint256 amount = s.organizerEscrow[s.organizer];
        if (amount == 0) revert NoFundsToWithdraw();
        
        // Clear escrow before transfer (checks-effects-interactions)
        s.organizerEscrow[s.organizer] = 0;
        
        if (!s.idrxToken.transfer(s.organizer, amount)) revert WithdrawFailed();
        
        emit OrganizerFundsWithdrawn(s.organizer, amount);
    }

    /// @notice Processes refund for a specific user (called by NFT contract)
    /// @param to Address to receive the refund
    /// @param amount Amount to refund in IDRX tokens
    function processRefund(address to, uint256 amount) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        require(msg.sender == address(s.ticketNFT), "Only NFT contract can process refund");
        require(s.cancelled, "Event not cancelled");
        
        // Validate contract has sufficient balance
        require(s.idrxToken.balanceOf(address(this)) >= amount, "Insufficient contract balance");
        
        // Transfer from contract escrow
        bool success = s.idrxToken.transfer(to, amount);
        require(success, "Token transfer failed");
        
        // Update analytics
        s.totalRefunds += amount;
        
        emit RefundProcessed(to, amount);
    }

    /// @notice Emergency refund for individual ticket owners when event is cancelled
    /// @param tokenId Token ID of the ticket to refund
    function emergencyRefund(uint256 tokenId) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        require(s.cancelled, "Event not cancelled");
        require(s.ticketNFT.ownerOf(tokenId) == _msgSender(), "Not token owner");
        
        // Get ticket metadata for refund amount
        Structs.TicketMetadata memory metadata = s.ticketNFT.getTicketMetadata(tokenId);
        
        // Validate ticket status (always Algorithm 1)
        string memory status = s.ticketNFT.getTicketStatus(tokenId);
        require(keccak256(bytes(status)) == keccak256(bytes("valid")), "Ticket not eligible for refund");
        s.ticketNFT.updateStatus(tokenId, "refunded");
        
        uint256 refundAmount = metadata.originalPrice;
        
        // Transfer refund to ticket owner
        if (!s.idrxToken.transfer(_msgSender(), refundAmount)) revert TokenTransferFailed();
        
        // Update analytics
        s.totalRefunds += refundAmount;
        
        emit RefundProcessed(_msgSender(), refundAmount);
    }

    /// @notice Gets organizer escrow balance
    /// @param organizer Address of the organizer
    /// @return Escrow balance for the organizer
    function getOrganizerEscrow(address organizer) external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.organizerEscrow[organizer];
    }

    /// @notice Gets purchase statistics for an address
    /// @param user Address to check
    /// @return Number of tickets purchased by the user
    function getUserPurchaseCount(address user) external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.userPurchaseCount[user];
    }

    // ========== PLATFORM FEE FUNCTIONS ==========

    /// @notice Gets total platform fees collected
    /// @return Total platform fees available for withdrawal
    function getPlatformFeesBalance() external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.platformFeesCollected - s.platformFeesWithdrawn;
    }

    /// @notice Gets total platform fees collected (including withdrawn)
    /// @return Total platform fees ever collected
    function getTotalPlatformFeesCollected() external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.platformFeesCollected;
    }

    /// @notice Allows platform to withdraw collected fees
    /// @dev Only callable by factory (platform admin)
    function withdrawPlatformFees() external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        require(_msgSender() == s.factory, "Only platform can withdraw fees");
        
        uint256 availableFees = s.platformFeesCollected - s.platformFeesWithdrawn;
        if (availableFees == 0) revert NoFundsToWithdraw();
        
        // Update withdrawn amount before transfer (checks-effects-interactions)
        s.platformFeesWithdrawn += availableFees;
        
        // Transfer platform fees to factory
        if (!s.idrxToken.transfer(s.factory, availableFees)) revert WithdrawFailed();
        
        emit PlatformFeesWithdrawn(s.factory, availableFees);
    }

    /// @notice Gets sales statistics for a tier
    /// @param tierId Tier ID to check
    /// @return Number of tickets sold for the tier
    function getTierSalesCount(uint256 tierId) external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.tierSalesCount[tierId];
    }

    /// @notice Gets total revenue and refunds
    /// @return totalRevenue Total revenue generated
    /// @return totalRefunds Total refunds processed
    function getRevenueStats() external view returns (uint256 totalRevenue, uint256 totalRefunds) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return (s.totalRevenue, s.totalRefunds);
    }

    /// @notice Generates deterministic token ID for Algorithm 1 tickets
    /// @param _eventId Unique event identifier (0-999)
    /// @param tierCode Ticket tier identifier (0-9)
    /// @param sequential Sequential number within tier (1-99999)
    /// @return tokenId Deterministic token ID
    function _generateTokenId(
        uint256 _eventId,
        uint256 tierCode,
        uint256 sequential
    ) internal pure returns (uint256) {
        require(_eventId >= 1 && _eventId <= 999, "Event ID must be 1-999");
        require(tierCode <= 9, "Tier code too large");
        require(sequential <= 99999, "Sequential number too large");
        
        // Convert tier 0 to tier 1 for token ID format (1-based indexing)
        uint256 actualTierCode = tierCode + 1;
        
        return (1 * 1e9) + (_eventId * 1e6) + (actualTierCode * 1e4) + sequential;
    }

    /// @notice Checks if a token exists (Algorithm 1 only)
    /// @param tokenId Token ID to check
    /// @return True if token exists
    function ticketExists(uint256 tokenId) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.ticketExists[tokenId];
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

    /// @notice Converts an address to its string representation
    /// @param addr Address to convert
    /// @return String representation of the address
    function _addressToString(address addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    /// @notice Internal function to track new attendee efficiently (Phase 1.3)
    /// @param s AppStorage reference
    /// @param attendee Address of the new attendee
    /// @param tokenId Token ID that was minted for this attendee
    function _trackNewAttendee(LibAppStorage.AppStorage storage s, address attendee, uint256 tokenId) internal {
        // Add token to user's token array
        s.userTokenIds[attendee].push(tokenId);
        
        // Track token ownership
        s.tokenIdToOwner[tokenId] = attendee;
        
        // If first-time attendee, add to attendee list
        if (!s.isAttendee[attendee]) {
            s.isAttendee[attendee] = true;
            s.attendeeList.push(attendee);
        }
        
        // Increment total minted tokens counter
        s.totalMintedTokens++;
    }

    // Events
    event TicketPurchased(address indexed buyer, uint256 indexed tierId, uint256 quantity, uint256 totalPrice);
    event OrganizerFundsWithdrawn(address indexed organizer, uint256 amount);
    event PlatformFeesWithdrawn(address indexed platform, uint256 amount);
    event RefundProcessed(address indexed to, uint256 amount);
}