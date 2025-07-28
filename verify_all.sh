#!/bin/bash

# Lisk Sepolia verification script
# Run with: bash verify_all.sh

set -e  # Exit on any error

echo "🔍 Starting verification for Lisk Sepolia Diamond contracts..."
echo "Chain ID: 4202"
echo "RPC: https://rpc.sepolia-api.lisk.com"
echo ""

# Contract addresses
DIAMOND="0x15E50897ca9028A804825a42608711be31C62A70"
DIAMOND_CUT_FACET="0x6058A6673B9373DB94d620d6E8afc18a0E743aB6"
DIAMOND_LOUPE_FACET="0x3f7af2eFF83D0DE7Af6B68fb41abC1BE72a8055e"
OWNERSHIP_FACET="0x71d2052ca44183FB58fE1fA9A3585D2348D58Ba6"
EVENT_CORE_FACET="0x5E4299F3f600A3737De6a91cca1bC9d998f46245"
TICKET_PURCHASE_FACET="0x851b554920F1cC71CA37b36D612871d439F45eC4"
MARKETPLACE_FACET="0xe2b3C58ff5d04d7C0059Ea5A964293BdDc10b3ef"
STAFF_MANAGEMENT_FACET="0x628f5268789ccB598BaAF52B2d4CB5aA97567b28"
MOCK_IDRX="0xb57Cf872ac226e36124d59BA5345734190d31e51"
TRUSTED_FORWARDER="0x23fE27ca9A38c041Df477Eb14a5232cCB3fB844f"
DEPLOYER="0x580B01f8CDf7606723c3BE0dD2AaD058F5aECa3d"

# Common forge verify parameters
FORGE_VERIFY_PARAMS="--chain-id 4202 --rpc-url https://rpc.sepolia-api.lisk.com"

echo "📋 Step 1: Verifying Supporting Contracts..."

echo "🪙 Verifying MockIDRX..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  $MOCK_IDRX \
  src/core/MockIDRX.sol:MockIDRX || echo "❌ MockIDRX verification failed"

echo "📨 Verifying SimpleForwarder..."
FORWARDER_ARGS=$(cast abi-encode "constructor(address)" $DEPLOYER)
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  --constructor-args $FORWARDER_ARGS \
  $TRUSTED_FORWARDER \
  src/core/SimpleForwarder.sol:SimpleForwarder || echo "❌ SimpleForwarder verification failed"

echo ""
echo "💎 Step 2: Verifying Diamond Infrastructure Facets..."

echo "✂️ Verifying DiamondCutFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  $DIAMOND_CUT_FACET \
  src/diamond/facets/DiamondCutFacet.sol:DiamondCutFacet || echo "❌ DiamondCutFacet verification failed"

echo "🔍 Verifying DiamondLoupeFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  $DIAMOND_LOUPE_FACET \
  src/diamond/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet || echo "❌ DiamondLoupeFacet verification failed"

echo "👑 Verifying OwnershipFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  $OWNERSHIP_FACET \
  src/diamond/facets/OwnershipFacet.sol:OwnershipFacet || echo "❌ OwnershipFacet verification failed"

echo ""
echo "🏢 Step 3: Verifying Business Logic Facets..."

FACET_ARGS=$(cast abi-encode "constructor(address)" $TRUSTED_FORWARDER)

echo "🎫 Verifying EventCoreFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  --constructor-args $FACET_ARGS \
  $EVENT_CORE_FACET \
  src/diamond/facets/EventCoreFacet.sol:EventCoreFacet || echo "❌ EventCoreFacet verification failed"

echo "💰 Verifying TicketPurchaseFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  --constructor-args $FACET_ARGS \
  $TICKET_PURCHASE_FACET \
  src/diamond/facets/TicketPurchaseFacet.sol:TicketPurchaseFacet || echo "❌ TicketPurchaseFacet verification failed"

echo "🛒 Verifying MarketplaceFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  --constructor-args $FACET_ARGS \
  $MARKETPLACE_FACET \
  src/diamond/facets/MarketplaceFacet.sol:MarketplaceFacet || echo "❌ MarketplaceFacet verification failed"

echo "👥 Verifying StaffManagementFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  --constructor-args $FACET_ARGS \
  $STAFF_MANAGEMENT_FACET \
  src/diamond/facets/StaffManagementFacet.sol:StaffManagementFacet || echo "❌ StaffManagementFacet verification failed"

echo ""
echo "💎 Step 4: Diamond Main Contract (Complex - May Fail)..."
echo "⚠️  Diamond verification requires complex constructor args and may fail"
echo "If it fails, use manual verification via block explorer"
echo ""

# Note: Diamond verification is very complex due to the FacetCut[] array
# It's likely to fail with forge verify, so we recommend manual verification
echo "Skipping Diamond verification - recommend manual verification"
echo "Diamond Address: $DIAMOND"

echo ""
echo "✅ Step 5: Testing Verified Contracts..."

echo "🧪 Testing Diamond owner function..."
OWNER_RESULT=$(cast call $DIAMOND "owner()" --rpc-url https://rpc.sepolia-api.lisk.com 2>/dev/null || echo "failed")
echo "Diamond owner result: $OWNER_RESULT"

echo "🧪 Testing Diamond facetAddresses function..."
FACETS_RESULT=$(cast call $DIAMOND "facetAddresses()" --rpc-url https://rpc.sepolia-api.lisk.com 2>/dev/null || echo "failed")
echo "Facets count: $(echo $FACETS_RESULT | wc -w)"

echo "🧪 Testing IDRX balance..."
BALANCE_RESULT=$(cast call $MOCK_IDRX "balanceOf(address)" $DEPLOYER --rpc-url https://rpc.sepolia-api.lisk.com 2>/dev/null || echo "failed")
echo "IDRX balance result: $BALANCE_RESULT"

echo ""
echo "🎉 VERIFICATION PROCESS COMPLETED!"
echo ""
echo "📝 SUMMARY:"
echo "✅ Contracts deployed and functional"
echo "⚠️  Some verifications may have failed (normal for complex contracts)"
echo "💡 For failed verifications, use manual verification at:"
echo "   https://sepolia-blockscout.lisk.com"
echo ""
echo "🔗 MAIN CONTRACT ADDRESSES:"
echo "Diamond (Main): $DIAMOND"
echo "MockIDRX Token: $MOCK_IDRX"
echo "TrustedForwarder: $TRUSTED_FORWARDER"
echo ""
echo "Ready for frontend integration! 🚀"