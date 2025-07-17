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

// Custom errors
error AlreadyInitialized();
error OnlyEventContractCanCall();
error NotApprovedOrOwner();
error TicketAlreadyUsed();
error TicketDoesNotExist();
error InvalidOwner();
error InvalidTimestamp();

contract TicketNFT is ITicketNFT, ERC721Enumerable, ERC2771Context, ReentrancyGuard, Ownable {
    
    // State variables
    uint256 private _tokenIdCounter;
    address public eventContract;
    uint256 public eventId; // For Algorithm 1 token ID generation
    mapping(uint256 => uint256) public tierSequentialCounter; // Track sequential counter per tier
    mapping(uint256 => Structs.TicketMetadata) public ticketMetadata;
    mapping(uint256 => uint256) public transferCount;
    
    // Tambahan: mapping status burned
    mapping(uint256 => bool) public isBurned;
    
    // Algorithm 1 specific
    mapping(uint256 => string) public ticketStatus; // "valid", "used", "refunded"
    bool public useAlgorithm1;
    
    // Secret salt for QR challenge
    bytes32 private immutable _secretSalt;
    
    modifier onlyEventContract() {
        if(msg.sender != eventContract) revert OnlyEventContractCanCall();
        _;
    }
    
    constructor(address trustedForwarder) ERC721("Ticket", "TIX") ERC2771Context(trustedForwarder) Ownable(msg.sender) {
        _secretSalt = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender));
    }
    
    // Helper function to check if token exists
    function _tokenExists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    // Helper function to check if sender is approved or owner
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || 
                isApprovedForAll(owner, spender) || 
                getApproved(tokenId) == spender);
    }
    
    function initialize(
        string memory _eventName,
        string memory _symbol,
        address _eventContract
    ) external override {
        if(eventContract != address(0)) revert AlreadyInitialized();
        
        // Store the values in state variables even if we can't use them to rename the token
        string memory fullName = string(abi.encodePacked("Ticket - ", _eventName));
        emit InitializeLog(_eventName, _symbol, fullName);
        
        eventContract = _eventContract;
        
        // Transfer ownership to event contract
        _transferOwnership(_eventContract);
    }
    
    // Algorithm 1: Initialize with event ID
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
        useAlgorithm1 = true; // Set algorithm 1 mode
        
        // Transfer ownership to event contract
        _transferOwnership(_eventContract);
    }

    event InitializeLog(string eventName, string symbol, string fullName);
    
    function mintTicket(
        address to,
        uint256 tierId,
        uint256 originalPrice
    ) external override onlyEventContract nonReentrant returns (uint256) {
        return _mintTicketInternal(to, _tokenIdCounter, tierId, originalPrice);
    }
    
    // Algorithm 1: Mint with specific token ID
    function mintTicket(
        address to,
        uint256 tokenId,
        uint256 tierId,
        uint256 originalPrice
    ) public onlyEventContract nonReentrant returns (uint256) {
        return _mintTicketInternal(to, tokenId, tierId, originalPrice);
    }
    
    // Algorithm 1: Generate token ID according to spec
    // Format: 1[eventId][tier][sequential]
    function generateTokenId(
        uint256 _eventId,
        uint256 tierCode,
        uint256 sequential
    ) internal pure returns (uint256) {
        require(_eventId <= 999, "Event ID must be 3 digits max");
        require(tierCode <= 9, "Tier code must be 0-9");
        require(sequential <= 99999, "Sequential must be 5 digits max");
        
        // Convert tier 0 to tier 1 for token ID format
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
    
    function generateTicketHash(uint256 tokenId) public view override returns (bytes32) {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        if(ticketMetadata[tokenId].used) revert TicketAlreadyUsed();
        
        // Generate hash from token ID and secret salt
        return keccak256(abi.encodePacked(
            tokenId,
            _secretSalt
        ));
    }
    
    function verifyTicket(
        uint256 tokenId,
        bytes32 ticketHash
    ) public view override returns (bool) {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        if(ticketMetadata[tokenId].used) revert TicketAlreadyUsed();
        
        // Generate expected hash from token ID
        bytes32 expectedHash = keccak256(abi.encodePacked(
            tokenId,
            _secretSalt
        ));
        
        // Verify hash matches
        return ticketHash == expectedHash;
    }
    
    function useTicket(uint256 tokenId) external override onlyEventContract {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        if(ticketMetadata[tokenId].used) revert TicketAlreadyUsed();
        
        // Mark ticket as used
        ticketMetadata[tokenId].used = true;
        
        // Algorithm 1: Update status
        if (useAlgorithm1) {
            ticketStatus[tokenId] = "used";
        }
        
        // Emit event
        emit TicketUsed(tokenId, ownerOf(tokenId));
    }
    
    // Algorithm 1: Update ticket status
    function updateStatus(uint256 tokenId, string memory newStatus) external onlyEventContract {
        require(useAlgorithm1, "Only for Algorithm 1");
        require(_tokenExists(tokenId), "Token does not exist");
        
        string memory oldStatus = ticketStatus[tokenId];
        ticketStatus[tokenId] = newStatus;
        
        if (keccak256(bytes(newStatus)) == keccak256(bytes("used"))) {
            ticketMetadata[tokenId].used = true;
        }
        
        emit StatusUpdated(tokenId, oldStatus, newStatus);
    }
    
    // Algorithm 1: Get ticket status
    function getTicketStatus(uint256 tokenId) external view returns (string memory) {
        if (useAlgorithm1) {
            require(_tokenExists(tokenId), "Token does not exist");
            return ticketStatus[tokenId];
        } else {
            // Original algorithm
            require(_tokenExists(tokenId), "Token does not exist");
            return ticketMetadata[tokenId].used ? "used" : "valid";
        }
    }
    
    // Algorithm 1: Claim refund
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
    
    // Set algorithm mode
    function setAlgorithm1(bool _useAlgorithm1) external {
        require(msg.sender == eventContract || msg.sender == owner(), "Only event contract or owner can set algorithm");
        useAlgorithm1 = _useAlgorithm1;
    }
    
    function getTicketMetadata(uint256 tokenId) external view override returns (Structs.TicketMetadata memory) {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        return ticketMetadata[tokenId];
    }
    
    function markTransferred(uint256 tokenId) external override onlyEventContract {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        transferCount[tokenId]++;
    }
    
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if(!_tokenExists(tokenId)) revert TicketDoesNotExist();
        
        // In the actual implementation, this could be developed to return the appropriate URI
        // for example, metadata from IPFS based on tokenId and event metadata
        return "https://example.com/api/ticket/metadata";
    }
    
    // Override _msgSender for ERC2771Context
    function _msgSender() internal view override(Context, ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }
    
    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
    
    function _contextSuffixLength() internal view virtual override(Context, ERC2771Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }
    
    // Override transfer functions to support gasless transactions
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721, IERC721) nonReentrant {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);
    }
    
    // We need to explicitly override these functions to satisfy both IERC721 and ITicketNFT interfaces
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    
    // Fungsi burn NFT
    function burn(uint256 tokenId) external nonReentrant {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApprovedOrOwner();
        if (!_tokenExists(tokenId)) revert TicketDoesNotExist();
        _burn(tokenId);
        isBurned[tokenId] = true;
        emit TicketBurned(msg.sender, tokenId, block.timestamp);
    }
    
    // Fungsi generate dynamic QR hanya jika sudah burn
    function generateDynamicQR(uint256 tokenId) external view returns (bytes32) {
        require(isBurned[tokenId], "TicketNotBurned");
        uint256 timeBlock = block.timestamp / 1800; // 30 menit
        return keccak256(abi.encodePacked(tokenId, msg.sender, timeBlock, _secretSalt));
    }
    
    // Events
    event TicketMinted(uint256 indexed tokenId, address indexed to, uint256 tierId);
    event TicketTransferred(uint256 indexed tokenId, address indexed from, address indexed to);
    event TicketUsed(uint256 indexed tokenId, address indexed user);
    event TicketBurned(address indexed user, uint256 indexed tokenId, uint256 timestamp);
    
    // Algorithm 1 events
    event StatusUpdated(uint256 indexed tokenId, string oldStatus, string newStatus);
    event TicketRefunded(uint256 indexed tokenId, address indexed owner);
}