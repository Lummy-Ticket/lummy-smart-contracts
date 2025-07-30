// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

library Constants {
    // Basis point untuk perhitungan persentase (100% = 10000 basis poin)
    uint256 constant BASIS_POINTS = 10000;
    
    // Platform fees (revised business model)
    uint256 constant PLATFORM_PRIMARY_FEE_PERCENTAGE = 700;  // 7% on primary ticket sales
    uint256 constant PLATFORM_RESALE_FEE_PERCENTAGE = 300;   // 3% on resale transactions
    
    // Jendela waktu validitas QR code (30 detik)
    uint256 constant VALIDITY_WINDOW = 30;
    
    // Default maksimum markup untuk resale (20%)
    uint256 constant DEFAULT_MAX_MARKUP_PERCENTAGE = 2000;
}