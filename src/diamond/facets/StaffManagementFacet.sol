// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {LibAppStorage} from "src/diamond/LibAppStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/utils/Context.sol";
import "src/libraries/Structs.sol";
import "src/interfaces/ITicketNFT.sol";

/// @title StaffManagementFacet - Staff role management functionality facet
/// @author Lummy Protocol Team
/// @notice Handles staff role assignment, removal, and ticket scanning operations
/// @dev Part of Diamond pattern implementation - ~15KB target size
contract StaffManagementFacet is ReentrancyGuard, ERC2771Context {
    using LibAppStorage for LibAppStorage.AppStorage;

    /// @notice Custom errors for gas efficiency
    error InvalidStaffAddress();
    error CannotAssignNoneRole();
    error OnlyOrganizerCanAssignManager();
    error CannotRemoveOrganizer();
    error StaffHasNoRole();
    error OnlyOrganizerCanRemoveManager();
    error InsufficientStaffPrivileges();

    /// @notice Constructor for ERC2771 context
    /// @param trustedForwarder Address of trusted forwarder for gasless transactions
    constructor(address trustedForwarder) ERC2771Context(trustedForwarder) {}

    /// @notice Assigns a role to a staff member with hierarchical access control
    /// @param staff Address of the staff member to assign role to
    /// @param role Role to assign from StaffRole enum (SCANNER, CHECKIN, MANAGER)
    function addStaffWithRole(address staff, LibAppStorage.StaffRole role) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Check minimum privilege level (MANAGER can assign roles)
        if (s.staffRoles[_msgSender()] < LibAppStorage.StaffRole.MANAGER) {
            revert InsufficientStaffPrivileges();
        }
        
        if (staff == address(0)) revert InvalidStaffAddress();
        if (role == LibAppStorage.StaffRole.NONE) revert CannotAssignNoneRole();
        
        // Prevent privilege escalation: only organizer can assign MANAGER role
        if (role == LibAppStorage.StaffRole.MANAGER && _msgSender() != s.organizer) {
            revert OnlyOrganizerCanAssignManager();
        }
        
        s.staffRoles[staff] = role;
        s.staffWhitelist[staff] = true; // Maintain legacy compatibility
        
        emit StaffRoleAssigned(staff, role, _msgSender());
    }

    /// @notice Removes a staff member's role and access privileges
    /// @param staff Address of the staff member to remove
    function removeStaffRole(address staff) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Check minimum privilege level (MANAGER can remove roles)
        if (s.staffRoles[_msgSender()] < LibAppStorage.StaffRole.MANAGER) {
            revert InsufficientStaffPrivileges();
        }
        
        if (staff == s.organizer) revert CannotRemoveOrganizer();
        if (s.staffRoles[staff] == LibAppStorage.StaffRole.NONE) revert StaffHasNoRole();
        
        // Prevent privilege escalation: only organizer can remove MANAGER role
        if (s.staffRoles[staff] == LibAppStorage.StaffRole.MANAGER && _msgSender() != s.organizer) {
            revert OnlyOrganizerCanRemoveManager();
        }
        
        s.staffRoles[staff] = LibAppStorage.StaffRole.NONE;
        s.staffWhitelist[staff] = false; // Update legacy compatibility
        
        emit StaffRoleRemoved(staff, _msgSender());
    }

    /// @notice Legacy function to add staff with default SCANNER role
    /// @param staff Address of the staff member to add
    function addStaff(address staff) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        require(_msgSender() == s.organizer, "Only organizer can add staff");
        
        if (staff == address(0)) revert InvalidStaffAddress();
        
        s.staffWhitelist[staff] = true;
        s.staffRoles[staff] = LibAppStorage.StaffRole.SCANNER; // Default role
        
        emit StaffAdded(staff, _msgSender());
    }

    /// @notice Legacy function to remove staff member
    /// @param staff Address of the staff member to remove
    function removeStaff(address staff) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        require(_msgSender() == s.organizer, "Only organizer can remove staff");
        
        if (staff == s.organizer) revert CannotRemoveOrganizer();
        
        s.staffWhitelist[staff] = false;
        s.staffRoles[staff] = LibAppStorage.StaffRole.NONE;
        
        emit StaffRemoved(staff, _msgSender());
    }

    /// @notice Updates ticket status from valid to used (Algorithm 1 only)
    /// @param tokenId Token ID of the ticket to mark as used
    function updateTicketStatus(uint256 tokenId) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Check minimum privilege level (SCANNER can scan tickets)
        if (s.staffRoles[_msgSender()] < LibAppStorage.StaffRole.SCANNER) {
            revert InsufficientStaffPrivileges();
        }
        
        require(s.useAlgorithm1, "Only for Algorithm 1");
        require(s.ticketExists[tokenId], "Ticket does not exist");
        
        string memory currentStatus = s.ticketNFT.getTicketStatus(tokenId);
        require(keccak256(bytes(currentStatus)) == keccak256(bytes("valid")), "Ticket not valid");
        
        // Update status from "valid" to "used"
        s.ticketNFT.updateStatus(tokenId, "used");
        
        emit TicketStatusUpdated(tokenId, "valid", "used", _msgSender());
    }

    /// @notice Batch update multiple ticket statuses (for efficient check-in)
    /// @param tokenIds Array of token IDs to mark as used
    function batchUpdateTicketStatus(uint256[] calldata tokenIds) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Check minimum privilege level (SCANNER can scan tickets)
        if (s.staffRoles[_msgSender()] < LibAppStorage.StaffRole.SCANNER) {
            revert InsufficientStaffPrivileges();
        }
        
        require(s.useAlgorithm1, "Only for Algorithm 1");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            
            if (!s.ticketExists[tokenId]) continue; // Skip non-existent tickets
            
            string memory currentStatus = s.ticketNFT.getTicketStatus(tokenId);
            if (keccak256(bytes(currentStatus)) != keccak256(bytes("valid"))) continue; // Skip invalid tickets
            
            // Update status from "valid" to "used"
            s.ticketNFT.updateStatus(tokenId, "used");
            
            emit TicketStatusUpdated(tokenId, "valid", "used", _msgSender());
        }
        
        emit BatchTicketStatusUpdated(tokenIds, _msgSender());
    }

    /// @notice Validates a ticket without changing its status (for verification)
    /// @param tokenId Token ID to validate
    /// @return isValid True if ticket is valid and can be used
    /// @return owner Address of ticket owner
    /// @return tierId Tier ID of the ticket
    /// @return status Current status of the ticket
    function validateTicket(uint256 tokenId) external view returns (
        bool isValid,
        address owner,
        uint256 tierId,
        string memory status
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Check minimum privilege level (SCANNER can validate tickets)
        if (s.staffRoles[msg.sender] < LibAppStorage.StaffRole.SCANNER) {
            revert InsufficientStaffPrivileges();
        }
        
        if (s.useAlgorithm1) {
            if (!s.ticketExists[tokenId]) {
                return (false, address(0), 0, "nonexistent");
            }
            
            owner = s.ticketNFT.ownerOf(tokenId);
            status = s.ticketNFT.getTicketStatus(tokenId);
            isValid = keccak256(bytes(status)) == keccak256(bytes("valid"));
            
            // Get tier ID from ticket metadata
            Structs.TicketMetadata memory metadata = s.ticketNFT.getTicketMetadata(tokenId);
            tierId = metadata.tierId;
        } else {
            // Original algorithm validation
            try s.ticketNFT.ownerOf(tokenId) returns (address tokenOwner) {
                owner = tokenOwner;
                Structs.TicketMetadata memory metadata = s.ticketNFT.getTicketMetadata(tokenId);
                isValid = !metadata.used;
                tierId = metadata.tierId;
                status = metadata.used ? "used" : "valid";
            } catch {
                return (false, address(0), 0, "nonexistent");
            }
        }
    }

    /// @notice Gets staff role for an address
    /// @param account Address to check
    /// @return The staff role assigned to the address
    function getStaffRole(address account) external view returns (LibAppStorage.StaffRole) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.staffRoles[account];
    }

    /// @notice Checks if an address has sufficient privileges for a required role
    /// @param account Address to check
    /// @param requiredRole Minimum role required
    /// @return True if address has sufficient privileges
    function hasStaffRole(address account, LibAppStorage.StaffRole requiredRole) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.staffRoles[account] >= requiredRole;
    }

    /// @notice Checks if an address is in the staff whitelist (legacy function)
    /// @param account Address to check
    /// @return True if address is whitelisted staff
    function isStaff(address account) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.staffWhitelist[account];
    }

    /// @notice Gets all staff members with their roles (for admin interface)
    /// @dev This function is gas-intensive and should be used carefully
    /// @return staffMembers Array of staff addresses
    /// @return roles Array of corresponding roles
    function getAllStaff() external view returns (
        address[] memory staffMembers,
        LibAppStorage.StaffRole[] memory roles
    ) {
        // Note: This is a simplified implementation. In production, you'd want to maintain
        // a separate array of staff members to avoid iterating through all possible addresses
        
        // For this implementation, we'll return empty arrays and recommend
        // using events to track staff in the frontend
        staffMembers = new address[](0);
        roles = new LibAppStorage.StaffRole[](0);
    }

    /// @notice Gets role hierarchy information
    /// @return Array of role names in hierarchical order
    function getRoleHierarchy() external pure returns (string[] memory) {
        string[] memory roleNames = new string[](4);
        roleNames[0] = "NONE";
        roleNames[1] = "SCANNER";
        roleNames[2] = "CHECKIN";
        roleNames[3] = "MANAGER";
        return roleNames;
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
    event StaffRoleAssigned(address indexed staff, LibAppStorage.StaffRole role, address indexed assignedBy);
    event StaffRoleRemoved(address indexed staff, address indexed removedBy);
    event StaffAdded(address indexed staff, address indexed organizer);
    event StaffRemoved(address indexed staff, address indexed organizer);
    event TicketStatusUpdated(uint256 indexed tokenId, string oldStatus, string newStatus, address indexed scanner);
    event BatchTicketStatusUpdated(uint256[] tokenIds, address indexed scanner);
}