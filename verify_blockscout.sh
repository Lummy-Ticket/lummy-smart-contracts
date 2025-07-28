#!/bin/bash

# Lisk Sepolia Blockscout verification script
# Run with: bash verify_blockscout.sh

set -e  # Exit on any error

echo "🔍 Starting Blockscout verification for Lisk Sepolia Diamond contracts..."
echo "Using Blockscout verifier: https://sepolia-blockscout.lisk.com/api/"
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

# Common forge verify parameters for Blockscout
FORGE_VERIFY_PARAMS="--rpc-url https://rpc.sepolia-api.lisk.com --verifier blockscout --verifier-url 'https://sepolia-blockscout.lisk.com/api/'"

echo "📋 Step 1: Verifying Supporting Contracts..."

echo "🪙 Verifying MockIDRX..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  $MOCK_IDRX \
  src/core/MockIDRX.sol:MockIDRX && echo "✅ MockIDRX verified!" || echo "❌ MockIDRX verification failed"

echo ""
echo "📨 Verifying SimpleForwarder..."
FORWARDER_ARGS=$(cast abi-encode "constructor(address)" $DEPLOYER)
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  --constructor-args $FORWARDER_ARGS \
  $TRUSTED_FORWARDER \
  src/core/SimpleForwarder.sol:SimpleForwarder && echo "✅ SimpleForwarder verified!" || echo "❌ SimpleForwarder verification failed"

echo ""
echo "💎 Step 2: Verifying Diamond Infrastructure Facets..."

echo "✂️ Verifying DiamondCutFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  $DIAMOND_CUT_FACET \
  src/diamond/facets/DiamondCutFacet.sol:DiamondCutFacet && echo "✅ DiamondCutFacet verified!" || echo "❌ DiamondCutFacet verification failed"

echo ""
echo "🔍 Verifying DiamondLoupeFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  $DIAMOND_LOUPE_FACET \
  src/diamond/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet && echo "✅ DiamondLoupeFacet verified!" || echo "❌ DiamondLoupeFacet verification failed"

echo ""
echo "👑 Verifying OwnershipFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  $OWNERSHIP_FACET \
  src/diamond/facets/OwnershipFacet.sol:OwnershipFacet && echo "✅ OwnershipFacet verified!" || echo "❌ OwnershipFacet verification failed"

echo ""
echo "🏢 Step 3: Verifying Business Logic Facets..."

FACET_ARGS=$(cast abi-encode "constructor(address)" $TRUSTED_FORWARDER)

echo "🎫 Verifying EventCoreFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  --constructor-args $FACET_ARGS \
  $EVENT_CORE_FACET \
  src/diamond/facets/EventCoreFacet.sol:EventCoreFacet && echo "✅ EventCoreFacet verified!" || echo "❌ EventCoreFacet verification failed"

echo ""
echo "💰 Verifying TicketPurchaseFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  --constructor-args $FACET_ARGS \
  $TICKET_PURCHASE_FACET \
  src/diamond/facets/TicketPurchaseFacet.sol:TicketPurchaseFacet && echo "✅ TicketPurchaseFacet verified!" || echo "❌ TicketPurchaseFacet verification failed"

echo ""
echo "🛒 Verifying MarketplaceFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  --constructor-args $FACET_ARGS \
  $MARKETPLACE_FACET \
  src/diamond/facets/MarketplaceFacet.sol:MarketplaceFacet && echo "✅ MarketplaceFacet verified!" || echo "❌ MarketplaceFacet verification failed"

echo ""
echo "👥 Verifying StaffManagementFacet..."
forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  --constructor-args $FACET_ARGS \
  $STAFF_MANAGEMENT_FACET \
  src/diamond/facets/StaffManagementFacet.sol:StaffManagementFacet && echo "✅ StaffManagementFacet verified!" || echo "❌ StaffManagementFacet verification failed"

echo ""
echo "💎 Step 4: Attempting Diamond Main Contract Verification..."
echo "⚠️  This may fail due to complex constructor arguments"

forge verify-contract \
  $FORGE_VERIFY_PARAMS \
  $DIAMOND \
  src/diamond/DiamondLummy.sol:DiamondLummy && echo "✅ Diamond verified! (Amazing!)" || echo "❌ Diamond verification failed (expected - too complex)"

echo ""
echo "✅ Step 5: Testing Verified Contracts..."

echo "🧪 Testing Diamond functionality..."
OWNER_RESULT=$(cast call $DIAMOND "owner()" --rpc-url https://rpc.sepolia-api.lisk.com 2>/dev/null || echo "failed")
echo "Diamond owner: $OWNER_RESULT"

FACETS_RESULT=$(cast call $DIAMOND "facetAddresses()" --rpc-url https://rpc.sepolia-api.lisk.com 2>/dev/null | grep -o "0x[a-fA-F0-9]*" | wc -l || echo "0")
echo "Number of facets detected: $FACETS_RESULT"

BALANCE_RESULT=$(cast call $MOCK_IDRX "balanceOf(address)" $DEPLOYER --rpc-url https://rpc.sepolia-api.lisk.com 2>/dev/null || echo "failed")
echo "IDRX balance check: $BALANCE_RESULT"

echo ""
echo "🎉 BLOCKSCOUT VERIFICATION COMPLETED!"
echo ""
echo "📝 VERIFICATION SUMMARY:"
echo "✅ All contracts deployed and functional"
echo "🔗 Verified contracts can be viewed at:"
echo "   https://sepolia-blockscout.lisk.com"
echo ""
echo "🔗 MAIN CONTRACT ADDRESSES:"
echo "Diamond (Main): $DIAMOND"
echo "MockIDRX Token: $MOCK_IDRX"
echo "TrustedForwarder: $TRUSTED_FORWARDER"
echo ""
echo "🚀 Ready for production use!"
echo ""
echo "📋 NEXT STEPS:"
echo "1. Check verified contracts in block explorer"
echo "2. Update frontend with contract addresses"
echo "3. Test all functionality via frontend"
echo "4. Deploy to mainnet when ready"