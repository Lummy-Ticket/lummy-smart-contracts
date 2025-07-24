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

---

## 🔧 **Masalah yang Teridentifikasi & Revisi yang Diusulkan**

### 1. NFT Dynamic Metadata 🎨

#### **Kondisi Saat Ini**
```solidity
function tokenURI(uint256 tokenId) public view override returns (string memory) {
    return "https://example.com/api/ticket/metadata"; // URL Statis
}
```

#### **Masalah**
- Semua NFT menampilkan metadata yang sama tanpa memperhatikan status
- Pembeli di marketplace (OpenSea) tidak bisa membedakan tiket valid/bekas
- Tidak ada indikasi visual dari status tiket

#### **Solusi yang Diusulkan**
```solidity
function tokenURI(uint256 tokenId) public view override returns (string memory) {
    string memory status = getTicketStatus(tokenId);
    return string(abi.encodePacked(baseURI, "/", status, ".json"));
}
```

#### **Atribut yang Diharapkan**
- **Nama Event**: "Summer Music Festival 2025"
- **Tier**: "VIP", "Regular", "Economy"
- **Status**: "Valid" → "Used" → "Refunded"
- **Tanggal Event**: "2025-07-15"
- **Harga Asli**: "500000 IDRX"
- **Tanggal Pembelian**: Otomatis dari metadata

#### **Dampak**
- Pembeli bisa melihat status tiket sebelum membeli
- Diferensiasi visual mencegah penipuan
- Nilai koleksi yang meningkat untuk tiket bekas

---

### 2. Mekanisme Escrow untuk Perlindungan Buyer 🔒

#### **Kondisi Saat Ini**
```solidity
// User buy ticket → Organizer wallet (immediately)
// Tidak ada proteksi jika organizer scam/kabur
```

#### **Masalah**
- Organizer langsung dapat uang sebelum event selesai
- Tidak ada jaminan refund jika event dibatalkan
- Buyer berisiko kehilangan uang jika organizer tidak bertanggung jawab
- Organizer bisa habiskan uang sebelum event berlangsung

#### **Solusi yang Diusulkan**

**Fund Flow Baru:**
```
Current (Buruk):
User buy ticket → Organizer wallet (immediately)

Proposed (Lebih Baik):
User buy ticket → Event Contract (escrow) → Wait until event ends → Organizer claim
```

**Komponen Utama:**

**A. Escrow Storage:**
```solidity
mapping(uint256 => uint256) public eventEscrow; // eventId => total funds
mapping(uint256 => uint256) public eventEndTime; // eventId => timestamp
mapping(uint256 => EventStatus) public eventStatus; // eventId => status

enum EventStatus { ACTIVE, COMPLETED, CANCELLED, CLAIMED }
```

**B. Fund Holding Logic:**
- Contract menahan semua dana pembelian tiket
- Platform fee tetap langsung ke platform
- Bagian organizer ditahan sampai event selesai

**C. Release Conditions:**
- **Time-based**: Event sudah lewat end time
- **Manual trigger**: Organizer claim funds secara manual
- **Emergency**: Admin bisa release untuk edge cases

**D. Cancellation Protection:**
- Jika event cancel → automatic refund tersedia
- Dana sudah ada di contract, tidak perlu tunggu organizer approve

#### **State Management**
- `ACTIVE` - Event berlangsung, dana di escrow
- `COMPLETED` - Event selesai, organizer bisa claim
- `CANCELLED` - Event dibatalkan, buyer bisa refund
- `CLAIMED` - Organizer sudah ambil dana

#### **Security Considerations**
- Grace period setelah event berakhir (misal 7 hari) sebelum auto-release
- Dispute window untuk handle keluhan
- Platform admin bisa freeze dana jika ada dispute
- Multi-sig approval untuk emergency actions

#### **Strategi Implementasi**
- **Phase 1**: Basic escrow - Hold dana sampai event end time
- **Phase 2**: Advanced features - Partial releases, dispute resolution
- **Phase 3**: Smart escrow - Oracle integration, insurance mechanisms

#### **Dampak**
Layak diimplementasi untuk kesuksesan platform jangka panjang dan user trust, meskipun ada trade-off kompleksitas (cash flow delay organizer, logika contract lebih kompleks).

---

### 3. Penguatan Validasi Resale 🏪

#### **Kondisi Saat Ini**
- Contract memblokir tiket bekas di `listTicketForResale()`
- Frontend membutuhkan validasi yang konsisten

#### **Masalah**
- Validasi tidak konsisten di berbagai interface
- Potensi kebingungan user

#### **Solusi yang Diusulkan**
- Perkuat lapisan validasi frontend
- Tambahkan validasi API sebelum listing
- Pertahankan validasi contract (sudah diimplementasi)

#### **Area Implementasi**
- **Frontend**: Sembunyikan opsi resale untuk tiket bekas/refunded
- **API**: Pra-validasi sebelum interaksi contract
- **UI/UX**: Pesan yang jelas tentang kelayakan tiket

---

### 4. Implementasi Direct Wallet Gasless ⛽

#### **Kondisi Saat Ini**
- Infrastruktur ERC-2771 ada tapi `trustedForwarder = address(0)`
- Transaksi gasless dinonaktifkan

#### **Masalah**
- User harus bayar gas untuk operasi dasar
- Pengalaman user yang buruk untuk pendatang baru
- Hambatan masuk yang tinggi

#### **Solusi yang Diusulkan**
```solidity
function purchaseTicketForUser(
    address user,
    uint256 tierId,
    uint256 quantity,
    bytes calldata signature
) external onlyPlatform {
    require(verifySignature(user, tierId, quantity, signature), "Signature tidak valid");
    _purchaseTicket(user, tierId, quantity);
}
```

#### **Prioritas Fungsi Gasless**
1. **Purchase ticket** - Paling penting untuk onboarding user
2. **Update ticket status** - Operasi staff
3. **Claim refund** - Customer service

#### **Kebutuhan Implementasi**
- Sistem verifikasi signature
- Manajemen nonce untuk proteksi replay
- Rate limiting untuk mencegah abuse

---

### 5. Resale Marketplace Enumeration Problem 🏪

#### **Kondisi Saat Ini**
```solidity
// Contract tidak menyediakan cara untuk enumerate listed tickets
mapping(uint256 => ResaleInfo) public ticketResaleInfo;
```

#### **Masalah**
- Frontend tidak bisa list semua tickets yang dijual
- Marketplace page tidak bisa populate data
- Buyers tidak bisa browse available tickets
- Search dan filter tidak mungkin diimplementasi

#### **Solusi yang Diusulkan**
```solidity
uint256[] public listedTickets;
mapping(address => uint256[]) public sellerTickets;

function getListedTickets() external view returns (uint256[] memory) {
    return listedTickets;
}

function getSellerTickets(address seller) external view returns (uint256[] memory) {
    return sellerTickets[seller];
}
```

#### **Dampak**
- Marketplace functionality bisa diimplementasi
- Better user experience untuk browsing
- Search dan filter features possible

---

### 6. Staff Management Security Vulnerability 🔐

#### **Kondisi Saat Ini**
```solidity
mapping(address => bool) public staffWhitelist;
// Staff bisa akses semua functions tanpa restrictions
```

#### **Masalah**
- Staff punya unlimited access ke semua operations
- Tidak ada role-based permissions
- Staff bisa cancel events, change tiers, dll
- Security vulnerability untuk privilege escalation

#### **Solusi yang Diusulkan**
```solidity
enum StaffRole { SCANNER, CHECKIN, MANAGER }
mapping(address => StaffRole) public staffRoles;

modifier onlyStaffRole(StaffRole requiredRole) {
    require(staffRoles[msg.sender] >= requiredRole, "Insufficient privileges");
    _;
}
```

#### **Dampak**
- Better security dengan role-based access
- Granular permissions untuk different staff levels
- Reduced risk dari staff abuse

---

### 7. Algorithm Toggle Enforcement 🔄

#### **Kondisi Saat Ini**
```solidity
bool public useAlgorithm1;
// Tidak ada restrictions untuk switching mid-event
```

#### **Masalah**
- Algorithm bisa diubah ketika event sudah running
- Inconsistent behavior untuk existing tickets
- Possible exploitation untuk bypass validations
- Confusion antara algorithm implementations

#### **Solusi yang Diusulkan**
```solidity
bool public algorithmLocked;

modifier algorithmNotLocked() {
    require(!algorithmLocked, "Algorithm sudah terkunci");
    _;
}

function lockAlgorithm() external onlyOrganizer {
    algorithmLocked = true;
}
```

#### **Dampak**
- Consistency dalam event lifecycle
- Prevention dari mid-event algorithm switching
- Better predictability untuk users

---

### 8. Batch Operations untuk Gas Optimization ⛽

#### **Kondisi Saat Ini**
```solidity
// Users harus call purchaseTicket() multiple times
function purchaseTicket(uint256 tierId, uint256 quantity) external;
```

#### **Masalah**
- High gas costs untuk multiple ticket purchases
- Multiple transactions required
- Poor user experience
- Network congestion dari many small transactions

#### **Solusi yang Diusulkan**
```solidity
function batchPurchaseTickets(
    uint256[] calldata tierIds,
    uint256[] calldata quantities
) external {
    require(tierIds.length == quantities.length, "Array length mismatch");
    for (uint i = 0; i < tierIds.length; i++) {
        _purchaseTicket(tierIds[i], quantities[i]);
    }
}
```

#### **Dampak**
- Reduced gas costs per transaction
- Better user experience
- Less network congestion

---

## 🤔 **Pertanyaan Keamanan & Edge Case**

### **1. Risiko Collision Token ID**
**T**: Apakah event yang berbeda bisa memiliki token ID yang bertabrakan?  
**J**: ✅ **Aman** - Setiap event memiliki eventId unik dalam format token

### **2. Keamanan Signature**
**T**: Bagaimana mencegah replay attack dalam transaksi gasless?  
**J**: 🔧 **Membutuhkan** - Implementasi sistem nonce

### **3. Keamanan Platform Wallet**
**T**: Bagaimana jika platform wallet dikompromikan?  
**J**: 🔧 **Membutuhkan** - Sistem rate limiting dan monitoring

### **4. Caching Metadata**
**T**: Bagaimana memastikan marketplace menampilkan metadata terbaru?  
**J**: 📝 **Catatan** - Perlu refresh manual di OpenSea

### **5. Nilai Tiket Bekas**
**T**: Apakah tiket bekas memiliki nilai koleksi?  
**J**: ✅ **Ya** - Memorabilia event, jelas ditandai sebagai "USED"

### **6. Timing Pembatalan Event**
**T**: Bagaimana menangani refund jika event dibatalkan setelah beberapa tiket digunakan?  
**J**: 🤔 **Keputusan kebijakan** - Refund parsial vs penuh

### **7. Migrasi Algorithm**
**T**: Kompatibilitas dengan Algorithm 2 di masa depan?  
**J**: ✅ **Backward compatible** - Tiket Algorithm 1 tetap valid

### **8. Kelanjutan Counter**
**T**: Apakah sequential counter tier harus direset ketika diaktifkan kembali?  
**J**: ❌ **Tidak** - Lanjutkan penghitungan untuk mencegah collision token ID

---

## 🎯 **Prioritas Implementasi**

### **Fase 1: Issues Kritis (Blocking Production)**
1. **Escrow Mechanism** - Perlindungan buyer fundamental
2. **Staff Management Security** - Vulnerability critical
3. **Resale Marketplace Enumeration** - Core marketplace feature

### **Fase 2: Masalah Fungsionalitas Utama**
4. **NFT Dynamic Metadata** - Marketplace safety
5. **Algorithm Toggle Enforcement** - System consistency
6. **Batch Operations** - Gas optimization

### **Fase 3: Peningkatan UX & Validasi**
7. **Validasi Resale Strengthening** - User experience consistency
8. **Direct Wallet Gasless** - Onboarding improvement

---

## 🔧 **Kebutuhan Teknis**

### **Untuk Dynamic Metadata**
- Setup struktur IPFS dengan folder berbasis status
- Generasi gambar untuk status valid/used/refunded
- Template JSON metadata

### **Untuk Implementasi Escrow**
- Mapping storage untuk dana escrow per event
- Time-based release mechanisms
- Emergency controls dan multi-sig approval

### **Untuk Staff Security**
- Role-based access control implementation
- Granular permission system
- Privilege escalation prevention

### **Untuk Gasless Implementation**
- Library verifikasi signature
- Sistem manajemen nonce
- Implementasi rate limiting
- Langkah keamanan platform wallet

### **Untuk Keamanan**
- Pencegahan replay attack
- Review kontrol akses
- Mekanisme pause darurat

---

## 📝 **Catatan untuk Tim Development**

1. **Backward Compatibility**: Semua perubahan harus mempertahankan kompatibilitas dengan tiket yang ada
2. **Security First**: Implementasikan langkah keamanan sebelum penambahan fitur
3. **Testing Coverage**: Test komprehensif untuk semua edge case yang disebutkan
4. **Dokumentasi**: Update dokumentasi fungsi untuk fitur baru
5. **Optimasi Gas**: Pertimbangkan biaya gas untuk fungsi baru

---

**Status**: Siap untuk diskusi implementasi  
**Review Selanjutnya**: Setelah konsensus tim tentang prioritas