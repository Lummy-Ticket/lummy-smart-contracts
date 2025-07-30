// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "src/shared/libraries/Structs.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";

// Updated interface to extend IERC721 instead of duplicating methods
interface ITicketNFT is IERC721 {
    function initialize(
        string memory _eventName,
        string memory _symbol,
        address _eventContract
    ) external;
    
    function mintTicket(
        address to,
        uint256 tierId,
        uint256 originalPrice
    ) external returns (uint256);
    
    function mintTicket(
        address to,
        uint256 tokenId,
        uint256 tierId,
        uint256 originalPrice
    ) external returns (uint256);
    
    function transferTicket(address to, uint256 tokenId) external;
    
    function verifyTicketOwnership(uint256 tokenId) external view returns (bool);
    
    function useTicketByOwner(uint256 tokenId) external;
    
    function useTicket(uint256 tokenId) external;
    
    function getTicketMetadata(uint256 tokenId) external view returns (Structs.TicketMetadata memory);
    
    function markTransferred(uint256 tokenId) external;
    
    // Algorithm 1 functions
    function updateStatus(uint256 tokenId, string memory newStatus) external;
    function getTicketStatus(uint256 tokenId) external view returns (string memory);
    
    // We don't need to redeclare these methods from IERC721:
    // - transferFrom(address from, address to, uint256 tokenId)
    // - safeTransferFrom(address from, address to, uint256 tokenId)
    // - ownerOf(uint256 tokenId)
    // Since we're inheriting from IERC721
}