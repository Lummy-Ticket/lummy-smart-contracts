# Lummy Smart Contract - Catatan Revisi

## 📋 Status Implementasi Saat Ini

### ✅ **Fitur yang Sudah Berfungsi**
- **Implementasi Algorithm 1**: Pendekatan Pure Web3 dengan pembayaran langsung
- **Format Token ID**: `1[eventId][tier][sequential]` - tahan collision
- **Pembatasan Tiket Bekas**: Mencegah resale tiket yang sudah digunakan via fungsi custom
- **Pelacakan Status**: Manajemen status "valid", "used", "refunded"
- **Manajemen Staff**: Organizer bisa tambah/hapus staff untuk operasi check-in
- **Mekanisme Refund**: Burning NFT dengan proses refund otomatis
- **Infrastruktur ERC-2771**: Dukungan transaksi gasless (saat ini dinonaktifkan)

### 🔧 **Identified Issues & Proposed Revisions**

## 1. NFT Dynamic Metadata 🎨

### **Current State**
```solidity
function tokenURI(uint256 tokenId) public view override returns (string memory) {
    return "https://example.com/api/ticket/metadata"; // Static URL
}
```

### **Problem**
- All NFTs show same metadata regardless of status
- Buyers on marketplaces (OpenSea) cannot distinguish valid/used tickets
- No visual indication of ticket state

### **Proposed Solution**
```solidity
function tokenURI(uint256 tokenId) public view override returns (string memory) {
    string memory status = getTicketStatus(tokenId);
    return string(abi.encodePacked(baseURI, "/", status, ".json"));
}
```

### **Expected Traits**
- **Event Name**: "Summer Music Festival 2025"
- **Tier**: "VIP", "Regular", "Economy"
- **Status**: "Valid" → "Used" → "Refunded"
- **Event Date**: "2025-07-15"
- **Original Price**: "500000 IDRX"
- **Purchase Date**: Auto-generated from metadata

### **Impact**
- Buyers can see ticket status before purchase
- Visual differentiation prevents scams
- Enhanced collectible value for used tickets

---

## 2. Tier Management Enhancement 🎫

### **Current State**
```solidity
// Only addTicketTier() and updateTicketTier() exist
// No way to disable/remove tiers
```

### **Problem**
- Organizers cannot disable tiers after creation
- No flexibility for tier management
- Tiers remain purchasable even if no longer wanted

### **Proposed Solution**
```solidity
function disableTier(uint256 tierId) external onlyOrganizer {
    require(tierId < tierCount, "Tier does not exist");
    ticketTiers[tierId].active = false;
    emit TierDisabled(tierId);
}
```

### **Impact**
- Better tier management flexibility
- Organizers can respond to changing event requirements
- Existing sold tickets remain valid

---

## 3. Resale Validation Strengthening 🏪

### **Current State**
- Contract blocks used tickets in `listTicketForResale()`
- Frontend needs consistent validation

### **Problem**
- Inconsistent validation across different interfaces
- Potential user confusion

### **Proposed Solution**
- Strengthen frontend validation layers
- Add API validation before listing
- Maintain contract validation (already implemented)

### **Implementation Areas**
- **Frontend**: Hide resale options for used/refunded tickets
- **API**: Pre-validation before contract interaction
- **UI/UX**: Clear messaging about ticket eligibility

---

## 4. Direct Wallet Gasless Implementation ⛽

### **Current State**
- ERC-2771 infrastructure exists but `trustedForwarder = address(0)`
- Gasless transactions disabled

### **Problem**
- Users must pay gas for basic operations
- Poor user experience for newcomers
- High barrier to entry

### **Proposed Solution**
Add proxy functions for platform wallet execution:

```solidity
function purchaseTicketForUser(
    address user,
    uint256 tierId,
    uint256 quantity,
    bytes calldata signature
) external onlyPlatform {
    require(verifySignature(user, tierId, quantity, signature), "Invalid signature");
    _purchaseTicket(user, tierId, quantity);
}
```

### **Gasless Functions Priority**
1. **Purchase ticket** - Most important for user onboarding
2. **Update ticket status** - Staff operations
3. **Claim refund** - Customer service

### **Implementation Requirements**
- Signature verification system
- Nonce management for replay protection
- Rate limiting to prevent abuse

---

## 5. Optional: Refund Deadline ⏰

### **Current State**
- Users can claim refunds indefinitely after event cancellation

### **Business Question**
Should there be a time limit for refund claims?

### **Proposed Implementation**
```solidity
uint256 public constant REFUND_DEADLINE = 30 days;

function claimRefund(uint256 tokenId) external {
    require(cancelled, "Event not cancelled");
    require(block.timestamp <= cancelledAt + REFUND_DEADLINE, "Refund deadline passed");
    // ... existing refund logic
}
```

### **Pros & Cons**
- **Pros**: Organizers can close books, finite liability
- **Cons**: Users might miss deadline, customer service issues

---

## 🤔 **Security & Edge Case Questions**

### **1. Token ID Collision Risk**
**Q**: Can different events have colliding token IDs?
**A**: ✅ **Safe** - Each event has unique eventId in token format

### **2. Staff Permission Management**
**Q**: What happens to staff permissions if organizer changes?
**A**: ⚠️ **Needs addressing** - Staff whitelist should reset or transfer

### **3. Signature Security**
**Q**: How to prevent replay attacks in gasless transactions?
**A**: 🔧 **Requires** - Nonce system implementation

### **4. Platform Wallet Security**
**Q**: What if platform wallet is compromised?
**A**: 🔧 **Requires** - Rate limiting and monitoring systems

### **5. Metadata Caching**
**Q**: How to ensure marketplaces show updated metadata?
**A**: 📝 **Note** - Manual refresh required on OpenSea

### **6. Used Ticket Value**
**Q**: Do used tickets have collectible value?
**A**: ✅ **Yes** - Event memorabilia, clearly marked as "USED"

### **7. Tier Disable Impact**
**Q**: What happens to existing tickets when tier is disabled?
**A**: ✅ **No impact** - Existing tickets remain valid

### **8. Event Cancellation Timing**
**Q**: How to handle refunds if event cancelled after some tickets used?
**A**: 🤔 **Policy decision** - Partial vs full refunds

### **9. Algorithm Migration**
**Q**: Compatibility with future Algorithm 2?
**A**: ✅ **Backward compatible** - Algorithm 1 tickets remain valid

### **10. Counter Continuation**
**Q**: Should tier sequential counters reset when re-enabled?
**A**: ❌ **No** - Continue counting to prevent token ID collisions

---

## 🎯 **Implementation Priority**

### **Phase 1: Critical Issues**
1. **NFT Dynamic Metadata** - Marketplace safety
2. **Tier Disable Function** - Operational flexibility
3. **Resale Validation** - User experience consistency

### **Phase 2: UX Improvements**
4. **Direct Wallet Gasless** - Better user onboarding
5. **Signature Security** - Nonce system implementation

### **Phase 3: Policy Decisions**
6. **Refund Deadline** - Business requirement clarification

---

## 🔧 **Technical Requirements**

### **For Dynamic Metadata**
- IPFS structure setup with status-based folders
- Image generation for valid/used/refunded states
- Metadata JSON templates

### **For Gasless Implementation**
- Signature verification library
- Nonce management system
- Rate limiting implementation
- Platform wallet security measures

### **For Security**
- Replay attack prevention
- Access control reviews
- Emergency pause mechanisms

---

## 📝 **Notes for Development Team**

1. **Backward Compatibility**: All changes should maintain compatibility with existing tickets
2. **Security First**: Implement security measures before feature additions
3. **Testing Coverage**: Comprehensive tests for all edge cases mentioned
4. **Documentation**: Update function documentation for new features
5. **Gas Optimization**: Consider gas costs for new functions

---

**Last Updated**: January 17, 2025
**Status**: Ready for implementation discussion
**Next Review**: After team consensus on priorities