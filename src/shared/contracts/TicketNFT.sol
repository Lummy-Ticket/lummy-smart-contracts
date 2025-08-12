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
import "src/shared/libraries/Structs.sol";
import "src/shared/libraries/Constants.sol";
import "src/shared/libraries/Base64.sol";
import "src/shared/libraries/Strings.sol";
import "src/shared/interfaces/ITicketNFT.sol";

/// @notice Interface untuk get event info dari Diamond contract
interface IEventInfo {
    function getEventInfo() external view returns (
        string memory name,
        string memory description,
        uint256 date,
        string memory venue,
        string memory category,
        address organizer
    );
    function getIPFSMetadata() external view returns (string memory);
}

/**
 * @dev Gas-efficient custom errors for TicketNFT operations
 */
error AlreadyInitialized();
error OnlyEventContractCanCall();
error NotApprovedOrOwner();
error TicketAlreadyUsed();
error TicketDoesNotExist();
error InvalidOwner();
error InvalidTimestamp();

/**
 * @title TicketNFT Contract
 * @author Lummy Protocol Team
 * @notice NFT contract for event tickets with Algorithm 1 support
 * @dev Implements ERC-721 with enumerable extension, ERC-2771 for gasless transactions,
 *      enhanced metadata system, and OpenSea compatibility with dynamic traits.
 * @custom:version 2.0.0
 * @custom:security-contact security@lummy.io
 * @custom:standard ERC-721, ERC-2771
 */
contract TicketNFT is ITicketNFT, ERC721Enumerable, ERC2771Context, ReentrancyGuard, Ownable {
    using Strings for uint256;
    using Base64 for bytes;
    
    /* ========== STATE VARIABLES ========== */
    
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
    
    /// @dev Maps token IDs to their status ("valid", "used", "refunded")
    mapping(uint256 => string) public ticketStatus;
    
    /// @notice Base URI for NFT metadata
    string public baseTokenURI;
    
    /// @notice Base URI for NFT images
    string public baseImageURI;
    
    /* ========== MODIFIERS ========== */
    
    /**
     * @dev Restricts function access to the associated event contract only
     */
    modifier onlyEventContract() {
        if(msg.sender != eventContract) revert OnlyEventContractCanCall();
        _;
    }
    
    /* ========== CONSTRUCTOR ========== */
    
    /**
     * @notice Initializes the TicketNFT contract with ERC-2771 support
     * @param trustedForwarder Address of the trusted forwarder for gasless transactions
     */
    constructor(address trustedForwarder) ERC721("Ticket", "TIX") ERC2771Context(trustedForwarder) Ownable(msg.sender) {
        // Constructor simplified - algorithm-specific initialization handled in initialize functions
    }
    
    /* ========== HELPER FUNCTIONS ========== */
    
    /**
     * @dev Checks if a token exists by verifying it has an owner
     */
    function _tokenExists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    /**
     * @dev Checks if an address is approved to transfer a specific token
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || 
                isApprovedForAll(owner, spender) || 
                getApproved(tokenId) == spender);
    }
    
    /* ========== INITIALIZATION FUNCTIONS ========== */
    
    /**
     * @notice Initializes the NFT contract (ITicketNFT interface implementation)
     * @param _eventName Name of the event
     * @param _symbol Symbol for the NFT
     * @param _eventContract Address of the event contract
     */
    function initialize(
        string memory _eventName,
        string memory _symbol,
        address _eventContract
    ) external override {
        if(eventContract != address(0)) revert AlreadyInitialized();
        
        eventContract = _eventContract;
        
        // Transfer ownership to event contract for full control
        _transferOwnership(_eventContract);
        
        emit InitializeLog(_eventName, _symbol, string(abi.encodePacked("Ticket - ", _eventName)));
    }
    
    /**
     * @notice Initializes the NFT contract for Algorithm 1 events
     * @param _eventName Name of the event
     * @param _symbol Symbol for the NFT
     * @param _eventContract Address of the event contract
     * @param _eventId Unique event identifier for Algorithm 1
     */
    function initializeWithEventId(
        string memory _eventName,
        string memory _symbol,
        address _eventContract,
        uint256 _eventId
    ) external {
        if(eventContract != address(0)) revert AlreadyInitialized();
        
        eventContract = _eventContract;
        eventId = _eventId;
        
        // Transfer ownership to event contract for full control
        _transferOwnership(_eventContract);
        
        emit InitializeLog(_eventName, _symbol, string(abi.encodePacked("Ticket - ", _eventName)));
    }
    
    /* ========== TICKET MINTING ========== */
    
    /**
     * @notice Mints a ticket using Algorithm 1 (deterministic token ID)
     * @param to Address to receive the ticket NFT
     * @param tierId Ticket tier identifier
     * @param originalPrice Original price paid for the ticket
     * @return uint256 Token ID of the minted ticket
     */
    function mintTicket(
        address to,
        uint256 tierId,
        uint256 originalPrice
    ) external override onlyEventContract nonReentrant returns (uint256) {
        return _mintTicket(to, tierId, originalPrice);
    }
    
    /**
     * @notice Mints a ticket with provided token ID (Algorithm 1)
     * @param to Address to receive the ticket NFT
     * @param tokenId Pre-calculated deterministic token ID
     * @param tierId Ticket tier identifier
     * @param originalPrice Original price paid for the ticket
     * @return uint256 Token ID of the minted ticket
     */
    function mintTicket(
        address to,
        uint256 tokenId,
        uint256 tierId,
        uint256 originalPrice
    ) public override onlyEventContract nonReentrant returns (uint256) {
        return _mintTicketWithId(to, tokenId, tierId, originalPrice);
    }
    
    /**
     * @notice Generates deterministic token ID for Algorithm 1
     * @param _eventId Event identifier (0-999)
     * @param tierCode Tier identifier (0-9) 
     * @param sequential Sequential number within tier (1-99999)
     * @return uint256 Generated token ID
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
    
    /**
     * @dev Internal mint function with auto-generated token ID
     */
    function _mintTicket(
        address to,
        uint256 tierId,
        uint256 originalPrice
    ) internal returns (uint256) {
        // Generate deterministic token ID
        tierSequentialCounter[tierId]++;
        uint256 tokenId = generateTokenId(eventId, tierId, tierSequentialCounter[tierId]);
        return _mintTicketWithId(to, tokenId, tierId, originalPrice);
    }
    
    /**
     * @dev Internal mint function with provided token ID and enhanced metadata
     */
    function _mintTicketWithId(
        address to,
        uint256 tokenId,
        uint256 tierId,
        uint256 originalPrice
    ) internal returns (uint256) {
        // Mint the NFT
        _safeMint(to, tokenId);
        
        // Set ticket status (always Algorithm 1)
        ticketStatus[tokenId] = "valid";
        
        // Get serial number for this tier
        uint256 serialNumber = tierSequentialCounter[tierId];
        if (serialNumber == 0) {
            tierSequentialCounter[tierId]++;
            serialNumber = 1;
        }
        
        // Set enhanced metadata with placeholders (will be populated by event contract)
        ticketMetadata[tokenId] = Structs.TicketMetadata({
            eventId: eventId,
            tierId: tierId,
            originalPrice: originalPrice,
            used: false,
            purchaseDate: block.timestamp,
            eventName: "",        // To be set by event contract
            eventVenue: "",       // To be set by event contract
            eventDate: 0,         // To be set by event contract
            tierName: "",         // To be set by event contract
            organizerName: "",    // To be set by event contract
            serialNumber: serialNumber,
            status: "valid",
            transferCount: 0
        });
        
        // Initialize transfer count
        transferCount[tokenId] = 0;
        
        // Emit event
        emit TicketMinted(tokenId, to, tierId);
        
        return tokenId;
    }
    
    /* ========== TICKET USAGE ========== */
    
    /**
     * @notice Allows ticket owner to mark their own ticket as used
     */
    function useTicketByOwner(uint256 tokenId) external nonReentrant {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        if(ticketMetadata[tokenId].used) revert TicketAlreadyUsed();
        
        require(ownerOf(tokenId) == msg.sender, "Not ticket owner");
        
        // Mark ticket as used in metadata
        ticketMetadata[tokenId].used = true;
        
        // Always use Algorithm 1 - update status
        ticketStatus[tokenId] = "used";
        
        emit TicketUsed(tokenId, msg.sender);
    }
    
    /**
     * @notice Marks a ticket as used (called by event contract)
     */
    function useTicket(uint256 tokenId) external override onlyEventContract {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        if(ticketMetadata[tokenId].used) revert TicketAlreadyUsed();
        
        // Mark ticket as used in metadata
        ticketMetadata[tokenId].used = true;
        
        // Always use Algorithm 1 - update status
        ticketStatus[tokenId] = "used";
        
        emit TicketUsed(tokenId, ownerOf(tokenId));
    }
    
    /* ========== ALGORITHM 1 FUNCTIONS ========== */
    
    /**
     * @notice Updates ticket status for Algorithm 1 events
     */
    function updateStatus(uint256 tokenId, string memory newStatus) external override onlyEventContract {
        require(_tokenExists(tokenId), "Token does not exist");
        
        string memory oldStatus = ticketStatus[tokenId];
        ticketStatus[tokenId] = newStatus;
        
        // Update metadata status field juga (untuk OpenSea traits)
        ticketMetadata[tokenId].status = newStatus;
        
        if (keccak256(bytes(newStatus)) == keccak256(bytes("used"))) {
            ticketMetadata[tokenId].used = true;
        }
        
        emit StatusUpdated(tokenId, oldStatus, newStatus);
    }
    
    /**
     * @notice Gets the current status of a ticket
     */
    function getTicketStatus(uint256 tokenId) external view override returns (string memory) {
        require(_tokenExists(tokenId), "Token does not exist");
        return ticketStatus[tokenId];
    }
    
    /**
     * @notice Sets enhanced metadata for a ticket (used for OpenSea traits)
     */
    function setEnhancedMetadata(
        uint256 tokenId,
        string memory eventName,
        string memory eventVenue,
        uint256 eventDate,
        string memory tierName,
        string memory organizerName
    ) external onlyEventContract {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        
        Structs.TicketMetadata storage metadata = ticketMetadata[tokenId];
        metadata.eventName = eventName;
        metadata.eventVenue = eventVenue;
        metadata.eventDate = eventDate;
        metadata.tierName = tierName;
        metadata.organizerName = organizerName;
    }
    
    /* ========== TRANSFER FUNCTIONS ========== */
    
    /**
     * @notice Transfers a ticket to another address (ITicketNFT interface implementation)
     */
    function transferTicket(address to, uint256 tokenId) external override nonReentrant {
        if(!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApprovedOrOwner();
        if(ticketMetadata[tokenId].used) revert TicketAlreadyUsed();
        
        // Increment transfer count
        transferCount[tokenId]++;
        ticketMetadata[tokenId].transferCount++;
        
        // Transfer NFT
        _safeTransfer(msg.sender, to, tokenId, "");
    }
    
    /**
     * @notice Verifies ticket ownership (ITicketNFT interface implementation)
     */
    function verifyTicketOwnership(uint256 tokenId) external view override returns (bool) {
        if(!_tokenExists(tokenId)) return false;
        if(ticketMetadata[tokenId].used) revert TicketAlreadyUsed();
        return ownerOf(tokenId) == msg.sender;
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    /**
     * @notice Retrieves metadata for a specific ticket
     */
    function getTicketMetadata(uint256 tokenId) external view override returns (Structs.TicketMetadata memory) {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        return ticketMetadata[tokenId];
    }
    
    /**
     * @notice Marks a ticket as transferred (used by event contract)
     */
    function markTransferred(uint256 tokenId) external override onlyEventContract {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        transferCount[tokenId]++;
    }
    
    /**
     * @notice Returns the metadata URI for a token with dynamic generation
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        
        // Generate dynamic metadata JSON for OpenSea compatibility
        Structs.TicketMetadata memory metadata = ticketMetadata[tokenId];
        
        return string(abi.encodePacked(
            'data:application/json;base64,',
            _generateBase64JSON(tokenId, metadata)
        ));
    }
    
    /**
     * @dev Generates base64 encoded JSON metadata for OpenSea dengan dynamic content
     */
    function _generateBase64JSON(uint256 tokenId, Structs.TicketMetadata memory metadata) internal view returns (string memory) {
        // Generate image URL dari event IPFS hash (atau default)
        string memory imageUrl = _generateImageURL(metadata);
        
        // Generate OpenSea traits
        string memory traits = _generateTraitsArray(metadata);
        
        // Create complete JSON metadata
        string memory json = string(abi.encodePacked(
            '{"name":"Lummy Ticket #', tokenId.toString(), '",',
            '"description":"', _escapeJSON(metadata.eventName), ' - ', _escapeJSON(metadata.tierName), '",',
            '"image":"', imageUrl, '",',
            '"external_url":"https://lummy-ticket.vercel.app/ticket/', tokenId.toString(), '",',
            '"attributes":', traits,
            '}'
        ));
        
        // Encode to base64
        return Base64.encode(bytes(json));
    }

    /**
     * @dev Generates image URL untuk NFT (menggunakan event image dari IPFS)
     */
    function _generateImageURL(Structs.TicketMetadata memory metadata) internal view returns (string memory) {
        // Try to get IPFS hash dari event contract
        try IEventInfo(eventContract).getIPFSMetadata() returns (string memory ipfsHash) {
            if (bytes(ipfsHash).length > 0) {
                // Return IPFS URL
                return string(abi.encodePacked("https://gateway.pinata.cloud/ipfs/", ipfsHash));
            }
        } catch {
            // If failed to get from contract, use placeholder
        }
        
        // Fallback: placeholder image dengan unique identifier
        return string(abi.encodePacked(
            "https://api.lummy.io/nft/placeholder/",
            metadata.eventId.toString(),
            "/",
            metadata.tierId.toString(),
            "/",
            metadata.status
        ));
    }

    /**
     * @dev Generates OpenSea traits array untuk rich metadata
     */
    function _generateTraitsArray(Structs.TicketMetadata memory metadata) internal view returns (string memory) {
        // Get event category from the Diamond contract
        string memory eventCategory = _getEventCategory();
        
        return string(abi.encodePacked(
            '[',
            '{"trait_type":"Event","value":"', _escapeJSON(metadata.eventName), '"},',
            '{"trait_type":"Venue","value":"', _escapeJSON(metadata.eventVenue), '"},',
            '{"trait_type":"Date","value":"', _formatDate(metadata.eventDate), '"},',
            '{"trait_type":"Category","value":"', _escapeJSON(eventCategory), '"},',
            '{"trait_type":"Tier","value":"', _escapeJSON(metadata.tierName), '"},',
            '{"trait_type":"Status","value":"', metadata.status, '"},',
            '{"trait_type":"Original Price","value":"', metadata.originalPrice.toString(), ' IDRX"},',
            '{"trait_type":"Serial Number","value":"', metadata.serialNumber.toString(), '"},',
            '{"trait_type":"Organizer","value":"', _escapeJSON(metadata.organizerName), '"},',
            '{"trait_type":"Transfer Count","value":"', metadata.transferCount.toString(), '"}',
            ']'
        ));
    }

    /**
     * @dev Get event category from Diamond contract (Phase 1 - Enhanced Traits)
     */
    function _getEventCategory() internal view returns (string memory) {
        try IEventInfo(eventContract).getEventInfo() returns (
            string memory,
            string memory,
            uint256,
            string memory,
            string memory category,
            address
        ) {
            return category;
        } catch {
            return "General"; // Fallback category
        }
    }

    /**
     * @dev Format timestamp ke readable date
     */
    function _formatDate(uint256 timestamp) internal pure returns (string memory) {
        if (timestamp == 0) return "TBD";
        // Simplified: return timestamp. Dalam production bisa implement proper date formatting
        return timestamp.toString();
    }

    /**
     * @dev Escape JSON special characters (basic implementation)
     */
    function _escapeJSON(string memory str) internal pure returns (string memory) {
        // Basic implementation - dalam production perlu handle semua JSON escape chars
        bytes memory strBytes = bytes(str);
        if (strBytes.length == 0) return "";
        
        // Untuk sementara, return as is. Production implementation perlu escape ", \, dll
        return str;
    }
    
    /* ========== ERC2771 CONTEXT OVERRIDES ========== */
    
    function _msgSender() internal view override(Context, ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }
    
    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
    
    function _contextSuffixLength() internal view virtual override(Context, ERC2771Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    
    /* ========== EVENTS ========== */
    
    event InitializeLog(string eventName, string symbol, string fullName);
    event TicketMinted(uint256 indexed tokenId, address indexed to, uint256 tierId);
    event TicketUsed(uint256 indexed tokenId, address indexed user);
    event StatusUpdated(uint256 indexed tokenId, string oldStatus, string newStatus);
}