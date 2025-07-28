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
        
        if (s.useAlgorithm1) {
            _purchaseAlgorithm1(s, tier, _tierId, _quantity, totalPrice);
        } else {
            _purchaseOriginal(s, tier, _tierId, _quantity, totalPrice);
        }
        
        // Update sold count and analytics
        tier.sold += _quantity;
        s.tierSalesCount[_tierId] += _quantity;
        s.userPurchaseCount[_msgSender()] += _quantity;
        s.totalRevenue += totalPrice;
        
        emit TicketPurchased(_msgSender(), _tierId, _quantity, totalPrice);
    }

    /// @notice Internal function for Algorithm 1 purchases (escrow model)
    /// @param s App storage reference
    /// @param tier Ticket tier reference
    /// @param _tierId Tier ID
    /// @param _quantity Quantity to purchase
    /// @param totalPrice Total price for purchase
    function _purchaseAlgorithm1(
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
        
        // Add to organizer escrow
        s.organizerEscrow[s.organizer] += totalPrice;
        
        // Mint NFT tickets with deterministic Algorithm 1 token IDs
        for (uint256 i = 0; i < _quantity; i++) {
            uint256 tokenId = _generateTokenId(s.eventId, _tierId, tier.sold + i + 1);
            s.ticketNFT.mintTicket(_msgSender(), tokenId, _tierId, tier.price);
            s.ticketExists[tokenId] = true;
        }
    }

    /// @notice Internal function for Original algorithm purchases (immediate payment)
    /// @param s App storage reference
    /// @param tier Ticket tier reference
    /// @param _tierId Tier ID
    /// @param _quantity Quantity to purchase
    /// @param totalPrice Total price for purchase
    function _purchaseOriginal(
        LibAppStorage.AppStorage storage s,
        Structs.TicketTier storage tier,
        uint256 _tierId,
        uint256 _quantity,
        uint256 totalPrice
    ) internal {
        // Transfer tokens to contract first
        if (!s.idrxToken.transferFrom(_msgSender(), address(this), totalPrice)) {
            revert TokenTransferFailed();
        }
        
        // Calculate and distribute platform fee
        uint256 platformFee = (totalPrice * Constants.PLATFORM_FEE_PERCENTAGE) / Constants.BASIS_POINTS;
        if (!s.idrxToken.transfer(s.platformFeeReceiver, platformFee)) {
            revert PlatformFeeTransferFailed();
        }
        
        // Transfer organizer share immediately
        uint256 organizerShare = totalPrice - platformFee;
        if (!s.idrxToken.transfer(s.organizer, organizerShare)) {
            revert OrganizerPaymentFailed();
        }
        
        // Mint NFT tickets with sequential token IDs
        for (uint256 i = 0; i < _quantity; i++) {
            s.ticketNFT.mintTicket(_msgSender(), _tierId, tier.price);
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
        
        // Algorithm-specific validation
        if (s.useAlgorithm1) {
            string memory status = s.ticketNFT.getTicketStatus(tokenId);
            require(keccak256(bytes(status)) == keccak256(bytes("valid")), "Ticket not eligible for refund");
            s.ticketNFT.updateStatus(tokenId, "refunded");
        } else {
            require(!metadata.used, "Ticket already used");
        }
        
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
        require(_eventId <= 999, "Event ID too large");
        require(tierCode <= 9, "Tier code too large");
        require(sequential <= 99999, "Sequential number too large");
        
        // Convert tier 0 to tier 1 for token ID format
        uint256 actualTierCode = tierCode + 1;
        
        return (1 * 1e9) + (_eventId * 1e6) + (actualTierCode * 1e5) + sequential;
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

    // Events
    event TicketPurchased(address indexed buyer, uint256 indexed tierId, uint256 quantity, uint256 totalPrice);
    event OrganizerFundsWithdrawn(address indexed organizer, uint256 amount);
    event RefundProcessed(address indexed to, uint256 amount);
}