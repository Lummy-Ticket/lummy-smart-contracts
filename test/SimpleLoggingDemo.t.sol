// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/core/EventFactory.sol";
import "src/core/Event.sol";
import "src/core/TicketNFT.sol";
import "src/core/MockIDRX.sol";

contract SimpleLoggingDemo is Test {
    EventFactory public factory;
    Event public eventContract;
    TicketNFT public ticketNFT;
    MockIDRX public idrxToken;
    
    address public organizer;
    address public attendee1;
    address public attendee2;
    
    function setUp() public {
        organizer = makeAddr("organizer");
        attendee1 = makeAddr("attendee1");
        attendee2 = makeAddr("attendee2");
        
        // Deploy contracts
        idrxToken = new MockIDRX();
        factory = new EventFactory(address(idrxToken), address(0));
        
        // Create event
        vm.prank(organizer);
        address eventAddress = factory.createEvent(
            "Demo Event",
            "Event for logging demo",
            block.timestamp + 1 hours,
            "Demo Venue",
            "ipfs://demo-metadata",
            true // useAlgorithm1
        );
        
        eventContract = Event(eventAddress);
        address nftAddress = eventContract.getTicketNFT();
        ticketNFT = TicketNFT(nftAddress);
        
        // Add tiers
        vm.prank(organizer);
        eventContract.addTicketTier("Regular", 100 * 10**18, 100, 10);
        
        // Mint tokens
        idrxToken.mint(attendee1, 1000 * 10**18);
        idrxToken.mint(attendee2, 1000 * 10**18);
    }
    
    function testSimpleLoggingDemo() public {
        console.log("=== DEMO SKENARIO VERIFIKASI TIKET NFT ===");
        console.log("Demo ini menunjukkan langkah-langkah verifikasi tiket dengan detail");
        
        console.log("");
        console.log("--- Alamat-alamat Kontrak ---");
        console.log("Kontrak Event:");
        console.log(address(eventContract));
        console.log("Kontrak NFT:");
        console.log(address(ticketNFT));
        console.log("Token IDRX:");
        console.log(address(idrxToken));
        
        console.log("");
        console.log("--- Alamat-alamat Peserta ---");
        console.log("Organizer (Penyelenggara):");
        console.log(organizer);
        console.log("Attendee1 (Peserta 1):");
        console.log(attendee1);
        console.log("Attendee2 (Peserta 2):");
        console.log(attendee2);
        
        console.log("");
        console.log("--- Saldo Awal ---");
        console.log("Saldo IDRX Attendee1:");
        console.log(idrxToken.balanceOf(attendee1));
        console.log("Saldo IDRX Attendee2:");
        console.log(idrxToken.balanceOf(attendee2));
        
        console.log("");
        console.log("--- Proses Pembelian Tiket ---");
        console.log("Langkah 1: Attendee1 menyetujui pengeluaran IDRX");
        vm.startPrank(attendee1);
        uint256 ticketPrice = 100 * 10**18;
        idrxToken.approve(address(eventContract), ticketPrice);
        console.log("Jumlah yang disetujui:");
        console.log(ticketPrice);
        
        console.log("");
        console.log("Langkah 2: Attendee1 membeli tiket");
        uint256 eventId = factory.eventCounter() - 1;
        eventContract.purchaseTicket(0, 1);
        vm.stopPrank();
        console.log("Pembelian selesai");
        
        console.log("");
        console.log("--- Pembuatan Token ID ---");
        // Algorithm 1 token ID: 1[eventId][tier][sequential]
        uint256 expectedTokenId = (1 * 1e9) + (eventId * 1e6) + (1 * 1e5) + 1;
        console.log("Token ID yang diharapkan:");
        console.log(expectedTokenId);
        
        console.log("Breakdown Token ID:");
        console.log("  Algoritma: 1");
        console.log("  Event ID:");
        console.log(eventId);
        console.log("  Tier (1-indexed): 1");
        console.log("  Urutan: 1");
        
        console.log("");
        console.log("--- Verifikasi Token ---");
        address tokenOwner = ticketNFT.ownerOf(expectedTokenId);
        console.log("Pemilik token:");
        console.log(tokenOwner);
        console.log("Pemilik yang diharapkan:");
        console.log(attendee1);
        
        bool ownerCorrect = tokenOwner == attendee1;
        console.log("Verifikasi kepemilikan:");
        console.log(ownerCorrect ? "BENAR" : "SALAH");
        
        string memory tokenStatus = ticketNFT.getTicketStatus(expectedTokenId);
        console.log("Status token:");
        console.log(tokenStatus);
        
        console.log("");
        console.log("=== SIMULASI SKENARIO 6 LANGKAH VERIFIKASI TIKET ===");
        
        // LANGKAH 1: User scan berisi token id
        console.log("\n[LANGKAH 1] USER SCAN QR CODE BERISI TOKEN ID");
        console.log("User memindai QR code di pintu masuk venue");
        console.log("QR code berisi Token ID:", expectedTokenId);
        
        // LANGKAH 2: Smart contract verify NFT ownership dan status valid
        console.log("\n[LANGKAH 2] SMART CONTRACT VERIFY NFT OWNERSHIP DAN STATUS");
        console.log("Sistem melakukan verifikasi kepemilikan NFT...");
        vm.startPrank(attendee1);
        bool ownershipValid = ticketNFT.verifyTicketOwnership(expectedTokenId);
        vm.stopPrank();
        console.log("Hasil verifikasi kepemilikan:", ownershipValid ? "VALID" : "INVALID");
        console.log("Status tiket:", tokenStatus);
        
        // LANGKAH 3: Sistem inisiasi metadata update
        console.log("\n[LANGKAH 3] SISTEM INISIASI METADATA UPDATE");
        console.log("Sistem venue menginisiasi proses update metadata");
        console.log("Menyiapkan transaksi untuk mengubah status tiket");
        
        // LANGKAH 4: User menerima approval request
        console.log("\n[LANGKAH 4] USER MENERIMA APPROVAL REQUEST");
        console.log("User menerima notifikasi approval request di wallet");
        console.log("Request: Approve transaksi untuk mengubah status NFT");
        console.log("Fungsi yang akan dipanggil: useTicketByOwner(", expectedTokenId, ")");
        
        // LANGKAH 5: User approve dan metadata berubah
        console.log("\n[LANGKAH 5] USER APPROVE DAN METADATA STATUS BERUBAH");
        console.log("User mengklik 'Approve' di wallet");
        console.log("Menjalankan transaksi useTicketByOwner...");
        
        vm.startPrank(attendee1);
        ticketNFT.useTicketByOwner(expectedTokenId);
        vm.stopPrank();
        
        string memory newStatus = ticketNFT.getTicketStatus(expectedTokenId);
        console.log("Status tiket setelah approve:", newStatus);
        
        // LANGKAH 6: User bisa masuk venue
        console.log("\n[LANGKAH 6] USER BISA MASUK KE VENUE");
        console.log("Sistem venue memverifikasi status tiket telah berubah");
        console.log("Status tiket sekarang:", newStatus);
        console.log("Akses venue: DIIZINKAN");
        console.log("User berhasil masuk ke venue!");
        
        console.log("");
        console.log("--- Saldo Akhir ---");
        console.log("Saldo IDRX Attendee1 akhir:");
        console.log(idrxToken.balanceOf(attendee1));
        console.log("Saldo IDRX Organizer:");
        console.log(idrxToken.balanceOf(organizer));
        
        console.log("");
        console.log("=== DEMO SKENARIO VERIFIKASI TIKET BERHASIL ===");
        
        // Assertions
        assertEq(tokenOwner, attendee1);
        assertTrue(ownershipValid);
        assertEq(tokenStatus, "valid");
        assertEq(newStatus, "used");
    }
    
    function testStaffManagementDemo() public {
        console.log("=== DEMO MANAJEMEN STAFF ===");
        
        address staff1 = makeAddr("staff1");
        address staff2 = makeAddr("staff2");
        
        console.log("");
        console.log("--- Alamat-alamat Staff ---");
        console.log("Staff1:");
        console.log(staff1);
        console.log("Staff2:");
        console.log(staff2);
        
        console.log("");
        console.log("--- Status Staff Awal ---");
        bool staff1Initial = eventContract.staffWhitelist(staff1);
        bool staff2Initial = eventContract.staffWhitelist(staff2);
        console.log("Status awal Staff1:");
        console.log(staff1Initial ? "AKTIF" : "TIDAK AKTIF");
        console.log("Status awal Staff2:");
        console.log(staff2Initial ? "AKTIF" : "TIDAK AKTIF");
        
        console.log("");
        console.log("--- Menambahkan Staff ---");
        vm.startPrank(organizer);
        eventContract.addStaff(staff1);
        console.log("Staff1 berhasil ditambahkan");
        
        eventContract.addStaff(staff2);
        console.log("Staff2 berhasil ditambahkan");
        vm.stopPrank();
        
        console.log("");
        console.log("--- Status Staff Setelah Ditambahkan ---");
        bool staff1Added = eventContract.staffWhitelist(staff1);
        bool staff2Added = eventContract.staffWhitelist(staff2);
        console.log("Status Staff1 setelah ditambahkan:");
        console.log(staff1Added ? "AKTIF" : "TIDAK AKTIF");
        console.log("Status Staff2 setelah ditambahkan:");
        console.log(staff2Added ? "AKTIF" : "TIDAK AKTIF");
        
        console.log("");
        console.log("--- Menghapus Staff ---");
        vm.startPrank(organizer);
        eventContract.removeStaff(staff1);
        console.log("Staff1 berhasil dihapus");
        vm.stopPrank();
        
        console.log("");
        console.log("--- Status Staff Akhir ---");
        bool staff1Final = eventContract.staffWhitelist(staff1);
        bool staff2Final = eventContract.staffWhitelist(staff2);
        console.log("Status akhir Staff1:");
        console.log(staff1Final ? "AKTIF" : "TIDAK AKTIF");
        console.log("Status akhir Staff2:");
        console.log(staff2Final ? "AKTIF" : "TIDAK AKTIF");
        
        console.log("");
        console.log("=== DEMO MANAJEMEN STAFF SELESAI ===");
        
        // Assertions
        assertFalse(staff1Initial);
        assertFalse(staff2Initial);
        assertTrue(staff1Added);
        assertTrue(staff2Added);
        assertFalse(staff1Final);
        assertTrue(staff2Final);
    }
}