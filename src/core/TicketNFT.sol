// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC721} from "@openzeppelin/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {Context} from "@openzeppelin/utils/Context.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC165} from "@openzeppelin/utils/introspection/IERC165.sol";
import "src/libraries/Structs.sol";
import "src/libraries/Constants.sol";
import "src/libraries/SecurityLib.sol";
import "src/interfaces/ITicketNFT.sol";

/**
 * @dev Gas-efficient custom errors for TicketNFT operations
 */
error AlreadyInitialized(); /// @dev Thrown when attempting to initialize already initialized contract
error OnlyEventContractCanCall(); /// @dev Thrown when non-event contract calls restricted functions
error NotApprovedOrOwner(); /// @dev Thrown when caller lacks NFT transfer permissions
error TicketAlreadyUsed(); /// @dev Thrown when attempting operations on used tickets
error TicketDoesNotExist(); /// @dev Thrown when referencing non-existent token IDs
error InvalidOwner(); /// @dev Thrown when ownership validation fails
error InvalidTimestamp(); /// @dev Thrown when timestamp validation fails

/**
 * @title TicketNFT Contract
 * @author Lummy Protocol Team
 * @notice NFT contract for event tickets with dual algorithm support
 * @dev Implements ERC-721 with enumerable extension, ERC-2771 for gasless transactions,
 *      and supports both Algorithm 1 (deterministic IDs) and Original (sequential) modes.
 * @custom:version 2.0.0
 * @custom:security-contact security@lummy.io
 * @custom:standard ERC-721, ERC-2771
 */
contract TicketNFT is ITicketNFT, ERC721Enumerable, ERC2771Context, ReentrancyGuard, Ownable {
    
    /* ========== STATE VARIABLES ========== */
    
    /// @dev Internal counter for sequential token ID generation (Original algorithm)
    uint256 private _tokenIdCounter;
    
    /// @notice Address of the associated event contract
    address public eventContract;
    
    /// @notice Event ID for Algorithm 1 token generation
    uint256 public eventId;
    
    /// @dev Maps tier IDs to their sequential counters for Algorithm 1
    mapping(uint256 => uint256) public tierSequentialCounter;
    
    /// @dev Maps token IDs to their metadata
    mapping(uint256 => Structs.TicketMetadata) public ticketMetadata;
    
    /// @dev Tracks number of transfers per token for analytics
    mapping(uint256 => uint256) public transferCount;
    
    /// @dev Maps token IDs to their burn status
    mapping(uint256 => bool) public isBurned;
    
    /* ========== ALGORITHM 1 VARIABLES ========== */
    
    /// @dev Maps token IDs to their status ("valid", "used", "refunded")
    mapping(uint256 => string) public ticketStatus;
    
    /// @notice Whether this NFT contract uses Algorithm 1
    bool public useAlgorithm1;
    
    /* ========== MODIFIERS ========== */
    
    /**
     * @dev Restricts function access to the associated event contract only
     * @notice Ensures only the event contract can call sensitive functions
     */
    modifier onlyEventContract() {
        if(msg.sender != eventContract) revert OnlyEventContractCanCall();
        _;
    }
    
    /* ========== CONSTRUCTOR ========== */
    
    /**
     * @notice Initializes the TicketNFT contract with ERC-2771 support
     * @dev Sets up ERC-721 with default name/symbol and ERC-2771 context
     * @param trustedForwarder Address of the trusted forwarder for gasless transactions
     */
    constructor(address trustedForwarder) ERC721("Ticket", "TIX") ERC2771Context(trustedForwarder) Ownable(msg.sender) {
        // Constructor simplified - algorithm-specific initialization handled in initialize functions
    }
    
    /* ========== HELPER FUNCTIONS ========== */
    
    /**
     * @dev Checks if a token exists by verifying it has an owner
     * @param tokenId Token ID to check
     * @return bool True if token exists
     */
    function _tokenExists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    /**
     * @dev Checks if an address is approved to transfer a specific token
     * @param spender Address to check permissions for
     * @param tokenId Token ID to check
     * @return bool True if spender can transfer the token
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || 
                isApprovedForAll(owner, spender) || 
                getApproved(tokenId) == spender);
    }
    
    /* ========== INITIALIZATION FUNCTIONS ========== */
    
    /**
     * @notice Initializes the NFT contract for Original algorithm events
     * @dev Can only be called once. Sets event contract and transfers ownership.
     * @param _eventName Name of the event (for logging)
     * @param _symbol Symbol for the NFT (for logging) 
     * @param _eventContract Address of the event contract
     * @custom:security Can only be initialized once, ownership transferred to event
     * @custom:algorithm Original algorithm with sequential token IDs
     */
    function initialize(
        string memory _eventName,
        string memory _symbol,
        address _eventContract
    ) external override {
        if(eventContract != address(0)) revert AlreadyInitialized();
        
        string memory fullName = string(abi.encodePacked("Ticket - ", _eventName));
        emit InitializeLog(_eventName, _symbol, fullName);
        
        eventContract = _eventContract;
        
        // Transfer ownership to event contract for full control
        _transferOwnership(_eventContract);
    }
    
    /**
     * @notice Initializes the NFT contract for Algorithm 1 events
     * @dev Can only be called once. Sets event contract, event ID, and enables Algorithm 1.
     * @param _eventName Name of the event (for logging)
     * @param _symbol Symbol for the NFT (for logging)
     * @param _eventContract Address of the event contract
     * @param _eventId Unique event identifier for Algorithm 1
     * @custom:security Can only be initialized once, ownership transferred to event
     * @custom:algorithm-one Enables deterministic token IDs and status tracking
     */
    function initializeWithEventId(
        string memory _eventName,
        string memory _symbol,
        address _eventContract,
        uint256 _eventId
    ) external {
        if(eventContract != address(0)) revert AlreadyInitialized();
        
        string memory fullName = string(abi.encodePacked("Ticket - ", _eventName));
        emit InitializeLog(_eventName, _symbol, fullName);
        
        eventContract = _eventContract;
        eventId = _eventId;
        useAlgorithm1 = true;
        
        // Transfer ownership to event contract for full control
        _transferOwnership(_eventContract);
    }

    /* ========== EVENTS ========== */
    
    /// @notice Emitted during initialization with event details
    event InitializeLog(string eventName, string symbol, string fullName);
    
    /* ========== TICKET MINTING ========== */
    
    /**
     * @notice Mints a ticket using Original algorithm (sequential token ID)
     * @dev Only event contract can call. Uses internal counter for token ID.
     * @param to Address to receive the ticket NFT
     * @param tierId Ticket tier identifier
     * @param originalPrice Original price paid for the ticket
     * @return uint256 Token ID of the minted ticket
     * @custom:security Protected by onlyEventContract and nonReentrant
     * @custom:algorithm Original algorithm with sequential IDs
     */
    function mintTicket(
        address to,
        uint256 tierId,
        uint256 originalPrice
    ) external override onlyEventContract nonReentrant returns (uint256) {
        return _mintTicketInternal(to, _tokenIdCounter, tierId, originalPrice);
    }
    
    /**
     * @notice Mints a ticket using Algorithm 1 (deterministic token ID)
     * @dev Only event contract can call. Uses provided token ID.
     * @param to Address to receive the ticket NFT
     * @param tokenId Specific token ID to mint (Algorithm 1 format)
     * @param tierId Ticket tier identifier
     * @param originalPrice Original price paid for the ticket
     * @return uint256 Token ID of the minted ticket
     * @custom:security Protected by onlyEventContract and nonReentrant
     * @custom:algorithm-one Uses deterministic token ID format
     */
    function mintTicket(
        address to,
        uint256 tokenId,
        uint256 tierId,
        uint256 originalPrice
    ) public override onlyEventContract nonReentrant returns (uint256) {
        return _mintTicketInternal(to, tokenId, tierId, originalPrice);
    }
    
    /**
     * @notice Generates deterministic token ID for Algorithm 1
     * @dev Creates token ID in format: 1EEETTSSSS where EEE=eventId, TT=tier+1, SSSS=sequential
     * @param _eventId Event identifier (0-999)
     * @param tierCode Tier identifier (0-9) 
     * @param sequential Sequential number within tier (1-99999)
     * @return uint256 Generated token ID
     * @custom:format 1EEETTSSSS - ensures uniqueness across all events
     * @custom:algorithm-one Only used for Algorithm 1 events
     */
    function generateTokenId(
        uint256 _eventId,
        uint256 tierCode,
        uint256 sequential
    ) internal pure returns (uint256) {
        require(_eventId <= 999, "Event ID must be 3 digits max");
        require(tierCode <= 9, "Tier code must be 0-9");
        require(sequential <= 99999, "Sequential must be 5 digits max");
        
        // Convert tier 0 to tier 1 for token ID format (tiers 1-10)
        uint256 actualTierCode = tierCode + 1;
        
        return (1 * 1e9) + (_eventId * 1e6) + (actualTierCode * 1e5) + sequential;
    }
    
    // Internal mint function to avoid reentrancy conflicts
    function _mintTicketInternal(
        address to,
        uint256 tokenId,
        uint256 tierId,
        uint256 originalPrice
    ) internal returns (uint256) {
        if (useAlgorithm1) {
            // Algorithm 1: Generate token ID using spec format
            tierSequentialCounter[tierId]++;
            tokenId = generateTokenId(eventId, tierId, tierSequentialCounter[tierId]);
            _safeMint(to, tokenId);
            
            // Set Algorithm 1 status
            ticketStatus[tokenId] = "valid";
        } else {
            // Original algorithm: Generate sequential token ID
            tokenId = _tokenIdCounter;
            _tokenIdCounter++;
            _safeMint(to, tokenId);
        }
        
        // Set metadata
        ticketMetadata[tokenId] = Structs.TicketMetadata({
            eventId: 0,
            tierId: tierId,
            originalPrice: originalPrice,
            used: false,
            purchaseDate: block.timestamp
        });
        
        // Initialize transfer count
        transferCount[tokenId] = 0;
        
        // Emit event
        emit TicketMinted(tokenId, to, tierId);
        
        return tokenId;
    }
    
    /**
     * @notice Transfers a ticket to another address
     * @dev Protected by reentrancy guard. Validates transfer permissions and ticket status.
     * @param to Address to transfer the ticket to
     * @param tokenId Token ID of the ticket to transfer
     * @custom:security Validates sender permissions and ticket usage status
     * @custom:events Emits TicketTransferred event
     */
    function transferTicket(address to, uint256 tokenId) external override nonReentrant {
        if(!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApprovedOrOwner();
        if(ticketMetadata[tokenId].used) revert TicketAlreadyUsed();
        
        // Increment transfer count
        transferCount[tokenId]++;
        
        // Transfer NFT
        _safeTransfer(msg.sender, to, tokenId, "");
        
        // Emit event
        emit TicketTransferred(tokenId, msg.sender, to);
    }
    
    /**
     * @notice Verifies ticket ownership and validity
     * @dev Checks token existence, usage status, and caller ownership
     * @param tokenId Token ID to verify
     * @return bool True if caller owns the token and it's valid
     * @custom:security Validates token existence and usage status
     * @custom:validation Returns false for used or non-existent tickets
     */
    function verifyTicketOwnership(uint256 tokenId) public view returns (bool) {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        if(ticketMetadata[tokenId].used) revert TicketAlreadyUsed();
        
        // Simply verify that the caller owns the token
        return ownerOf(tokenId) == msg.sender;
    }
    
    /**
     * @notice Allows ticket owner to mark their own ticket as used
     * @dev Self-service ticket usage for ticket owners. Protected by reentrancy guard.
     *      Updates both metadata and Algorithm 1 status if applicable.
     * @param tokenId Token ID of the ticket to mark as used
     * @custom:security Only ticket owner can call, validates token status
     * @custom:self-service Allows owners to use their tickets without staff
     * @custom:algorithm-one Updates status to "used" for Algorithm 1 tickets
     */
    function useTicketByOwner(uint256 tokenId) external nonReentrant {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        if(ticketMetadata[tokenId].used) revert TicketAlreadyUsed();
        
        require(ownerOf(tokenId) == msg.sender, "Not ticket owner");
        
        // Mark ticket as used in metadata
        ticketMetadata[tokenId].used = true;
        
        // Update Algorithm 1 status if applicable
        if (useAlgorithm1) {
            ticketStatus[tokenId] = "used";
        }
        
        emit TicketUsed(tokenId, msg.sender);
    }
    
    /**
     * @notice Marks a ticket as used (called by event contract)
     * @dev Only event contract can call this function. Updates both metadata and Algorithm 1 status.
     * @param tokenId Token ID of the ticket to mark as used
     * @custom:security Only event contract can call
     * @custom:validation Checks token existence and usage status
     * @custom:algorithm-one Updates status to "used" for Algorithm 1 tickets
     */
    function useTicket(uint256 tokenId) external override onlyEventContract {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        if(ticketMetadata[tokenId].used) revert TicketAlreadyUsed();
        
        // Mark ticket as used in metadata
        ticketMetadata[tokenId].used = true;
        
        // Update Algorithm 1 status if applicable
        if (useAlgorithm1) {
            ticketStatus[tokenId] = "used";
        }
        
        emit TicketUsed(tokenId, ownerOf(tokenId));
    }
    
    /* ========== ALGORITHM 1 FUNCTIONS ========== */
    
    /**
     * @notice Updates ticket status for Algorithm 1 events
     * @dev Only event contract can call. Updates both Algorithm 1 status and metadata.
     * @param tokenId Token ID to update
     * @param newStatus New status to set ("valid", "used", "refunded")
     * @custom:security Only event contract can call
     * @custom:algorithm-one Only available for Algorithm 1 events
     * @custom:events Emits StatusUpdated event
     */
    function updateStatus(uint256 tokenId, string memory newStatus) external override onlyEventContract {
        require(useAlgorithm1, "Only for Algorithm 1");
        require(_tokenExists(tokenId), "Token does not exist");
        
        string memory oldStatus = ticketStatus[tokenId];
        ticketStatus[tokenId] = newStatus;
        
        if (keccak256(bytes(newStatus)) == keccak256(bytes("used"))) {
            ticketMetadata[tokenId].used = true;
        }
        
        emit StatusUpdated(tokenId, oldStatus, newStatus);
    }
    
    /**
     * @notice Gets the current status of a ticket
     * @dev Works for both Algorithm 1 and Original algorithms
     * @param tokenId Token ID to check
     * @return string Current ticket status
     * @custom:algorithm-one Returns Algorithm 1 status for Algorithm 1 events
     * @custom:original-algorithm Returns usage status for Original events
     */
    function getTicketStatus(uint256 tokenId) external view override returns (string memory) {
        if (useAlgorithm1) {
            require(_tokenExists(tokenId), "Token does not exist");
            return ticketStatus[tokenId];
        } else {
            // Original algorithm
            require(_tokenExists(tokenId), "Token does not exist");
            return ticketMetadata[tokenId].used ? "used" : "valid";
        }
    }
    
    /**
     * @notice Allows ticket holder to claim refund for cancelled Algorithm 1 events
     * @dev Only works for Algorithm 1 events. Validates cancellation status and burns NFT.
     * @param tokenId Token ID to claim refund for
     * @custom:security Protected by nonReentrant, validates ownership and event cancellation
     * @custom:algorithm-one Only available for Algorithm 1 events
     * @custom:refund Burns NFT after successful refund processing
     * @custom:events Emits TicketRefunded event
     */
    function claimRefund(uint256 tokenId) external nonReentrant {
        require(useAlgorithm1, "Only for Algorithm 1");
        require(_tokenExists(tokenId), "Token does not exist");
        require(ownerOf(tokenId) == _msgSender(), "Not token owner");
        require(
            keccak256(bytes(ticketStatus[tokenId])) == keccak256(bytes("valid")),
            "Ticket not eligible for refund"
        );
        
        // Check if event is cancelled (refund enabled)
        (bool success, bytes memory data) = eventContract.call(
            abi.encodeWithSignature("cancelled()")
        );
        require(success && abi.decode(data, (bool)), "Event not cancelled");
        
        // Update status to refunded
        ticketStatus[tokenId] = "refunded";
        
        // Get original price for refund
        uint256 refundAmount = ticketMetadata[tokenId].originalPrice;
        
        // Call event contract to process refund
        (bool refundSuccess, ) = eventContract.call(
            abi.encodeWithSignature("processRefund(address,uint256)", _msgSender(), refundAmount)
        );
        require(refundSuccess, "Refund processing failed");
        
        // Burn the NFT
        _burn(tokenId);
        
        emit TicketRefunded(tokenId, _msgSender());
    }
    
    /**
     * @notice Sets the algorithm mode for the NFT contract
     * @dev Only event contract or owner can call
     * @param _useAlgorithm1 True for Algorithm 1, false for Original
     * @custom:security Only event contract or owner can call
     * @custom:algorithm Controls which algorithm features are enabled
     */
    function setAlgorithm1(bool _useAlgorithm1) external {
        require(msg.sender == eventContract || msg.sender == owner(), "Only event contract or owner can set algorithm");
        useAlgorithm1 = _useAlgorithm1;
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    /**
     * @notice Retrieves metadata for a specific ticket
     * @dev Returns complete ticket metadata including purchase details
     * @param tokenId Token ID to get metadata for
     * @return Structs.TicketMetadata Complete ticket metadata
     * @custom:validation Checks token existence before returning data
     */
    function getTicketMetadata(uint256 tokenId) external view override returns (Structs.TicketMetadata memory) {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        return ticketMetadata[tokenId];
    }
    
    /**
     * @notice Marks a ticket as transferred (used by event contract)
     * @dev Only event contract can call. Increments transfer count for analytics.
     * @param tokenId Token ID to mark as transferred
     * @custom:security Only event contract can call
     * @custom:analytics Tracks transfer count for ticket history
     */
    function markTransferred(uint256 tokenId) external override onlyEventContract {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        transferCount[tokenId]++;
    }
    
    /**
     * @notice Returns the metadata URI for a token
     * @dev Standard ERC-721 function. Returns placeholder URI for now.
     * @param tokenId Token ID to get URI for
     * @return string Metadata URI (placeholder implementation)
     * @custom:future Could be enhanced to return IPFS-based metadata
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        
        // In the actual implementation, this could be developed to return the appropriate URI
        // for example, metadata from IPFS based on tokenId and event metadata
        return "https://example.com/api/ticket/metadata";
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
     * @notice Transfers token ownership with gasless transaction support
     * @dev Override to support ERC2771 gasless transactions. Protected by reentrancy guard.
     * @param from Current owner address
     * @param to New owner address
     * @param tokenId Token ID to transfer
     * @custom:security Protected by nonReentrant and permission validation
     * @custom:gasless Supports gasless transactions through trusted forwarder
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721, IERC721) nonReentrant {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);
    }
    
    /**
     * @dev Override supportsInterface to satisfy both IERC721 and ITicketNFT interfaces
     * @param interfaceId Interface identifier to check
     * @return bool True if interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    
    /* ========== BURN FUNCTIONS ========== */
    
    /**
     * @notice Burns a ticket NFT permanently
     * @dev Protected by reentrancy guard. Validates permissions and existence.
     * @param tokenId Token ID to burn
     * @custom:security Protected by nonReentrant and permission validation
     * @custom:burn Permanently destroys the NFT and marks as burned
     * @custom:events Emits TicketBurned event
     */
    function burn(uint256 tokenId) external nonReentrant {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApprovedOrOwner();
        if (!_tokenExists(tokenId)) revert TicketDoesNotExist();
        _burn(tokenId);
        isBurned[tokenId] = true;
        emit TicketBurned(msg.sender, tokenId, block.timestamp);
    }
    
    /**
     * @notice Generates dynamic QR code for burned tickets
     * @dev Only works for burned tickets. QR changes every 30 minutes.
     * @param tokenId Token ID to generate QR for
     * @return bytes32 Dynamic QR hash
     * @custom:security Only works for burned tickets
     * @custom:dynamic QR code changes every 30 minutes for security
     */
    function generateDynamicQR(uint256 tokenId) external view returns (bytes32) {
        require(isBurned[tokenId], "TicketNotBurned");
        uint256 timeBlock = block.timestamp / 1800; // 30 menit
        return keccak256(abi.encodePacked(tokenId, msg.sender, timeBlock));
    }
    
    /* ========== EVENTS ========== */
    
    /// @notice Emitted when a ticket NFT is minted
    event TicketMinted(uint256 indexed tokenId, address indexed to, uint256 tierId);
    
    /// @notice Emitted when a ticket is transferred between addresses
    event TicketTransferred(uint256 indexed tokenId, address indexed from, address indexed to);
    
    /// @notice Emitted when a ticket is marked as used
    event TicketUsed(uint256 indexed tokenId, address indexed user);
    
    /// @notice Emitted when a ticket NFT is burned
    event TicketBurned(address indexed user, uint256 indexed tokenId, uint256 timestamp);
    
    /// @notice Emitted when Algorithm 1 ticket status is updated
    event StatusUpdated(uint256 indexed tokenId, string oldStatus, string newStatus);
    
    /// @notice Emitted when a ticket refund is processed (Algorithm 1)
    event TicketRefunded(uint256 indexed tokenId, address indexed owner);
}