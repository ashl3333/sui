#!/bin/bash
# Script to deploy demo coin to testnet and setup test state

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Detect sui binary
if [ -x "../../../target/debug/sui" ]; then
    SUI_BIN="../../../target/debug/sui"
else
    SUI_BIN="sui"
fi

echo "=== Checkpoint Fork Demo: Deployment ==="
echo ""

# Check if sui client is configured
if ! "$SUI_BIN" client active-env &>/dev/null; then
    echo "Error: Sui client not configured. Please run 'sui client' to set up."
    exit 1
fi

# Switch to testnet
echo "Switching to testnet..."
"$SUI_BIN" client switch --env testnet || {
    echo "Warning: Testnet environment not found. Please add it with:"
    echo "  sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443"
    exit 1
}

ACTIVE_ADDRESS=$("$SUI_BIN" client active-address)
echo "Active address: $ACTIVE_ADDRESS"
echo ""

# Request testnet tokens if needed
echo "Note: Make sure you have testnet SUI tokens."
echo "Request tokens at: https://discord.com/channels/916379725201563759/971488439931392130"
echo ""
read -p "Press Enter to continue with deployment..."

# Build the package
echo "Building package..."
"$SUI_BIN" move build

# Publish the package
echo ""
echo "Publishing package to testnet..."
PUBLISH_OUTPUT=$("$SUI_BIN" client publish --gas-budget 100000000 --json)

# Extract package ID
PACKAGE_ID=$(echo "$PUBLISH_OUTPUT" | grep -o '"packageId":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "Package ID: $PACKAGE_ID"

# Extract TreasuryCap object ID
TREASURY_ID=$(echo "$PUBLISH_OUTPUT" | grep -o '"objectId":"[^"]*"' | grep -A 1 "TreasuryCap" | tail -1 | cut -d'"' -f4)
echo "TreasuryCap Object ID: $TREASURY_ID"

# Save deployment info
echo "$PACKAGE_ID" > .package_id
echo "$TREASURY_ID" > .treasury_id

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Package ID: $PACKAGE_ID"
echo "TreasuryCap ID: $TREASURY_ID"
echo ""
echo "Next steps:"
echo "1. Run ./setup_test_state.sh to mint and transfer coins"
echo "2. Note the checkpoint number from the transaction"
echo "3. Run tests with: sui move test --fork-checkpoint <CHECKPOINT> --fork-rpc-url https://fullnode.testnet.sui.io:443"
