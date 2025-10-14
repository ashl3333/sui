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
PUBLISH_OUTPUT=$("$SUI_BIN" client publish --gas-budget 100000000 --json 2>/dev/null)

# Save raw output for debugging
echo "$PUBLISH_OUTPUT" > .publish_output.json

# Extract package ID and TreasuryCap using Python
echo "Parsing transaction output..."
PARSED=$(python3 -c "
import json
import sys

output = '''$PUBLISH_OUTPUT'''

try:
    data = json.loads(output)

    # Extract package ID
    package_id = None
    if 'objectChanges' in data:
        for change in data['objectChanges']:
            if change.get('type') == 'published':
                package_id = change.get('packageId')
                break

    # Extract TreasuryCap ID
    treasury_id = None
    if 'objectChanges' in data:
        for change in data['objectChanges']:
            if change.get('type') == 'created':
                obj_type = change.get('objectType', '')
                if 'TreasuryCap' in obj_type:
                    treasury_id = change.get('objectId')
                    break

    if package_id and treasury_id:
        print(f'{package_id}|{treasury_id}')
    else:
        print('ERROR|ERROR', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)

if [[ "$PARSED" == ERROR* ]]; then
    echo "Error: Failed to parse transaction output"
    echo "Raw output saved to .publish_output.json"
    echo ""
    echo "Please manually extract:"
    echo "1. Package ID from the transaction"
    echo "2. TreasuryCap object ID"
    echo ""
    echo "Then create these files:"
    echo "  echo 'PACKAGE_ID' > .package_id"
    echo "  echo 'TREASURY_ID' > .treasury_id"
    exit 1
fi

PACKAGE_ID=$(echo "$PARSED" | cut -d'|' -f1)
TREASURY_ID=$(echo "$PARSED" | cut -d'|' -f2)

echo "Package ID: $PACKAGE_ID"
echo "TreasuryCap Object ID: $TREASURY_ID"

# Verify we got valid IDs
if [ -z "$PACKAGE_ID" ] || [ "$PACKAGE_ID" == "ERROR" ]; then
    echo "Error: Failed to extract Package ID"
    exit 1
fi

if [ -z "$TREASURY_ID" ] || [ "$TREASURY_ID" == "ERROR" ]; then
    echo "Error: Failed to extract TreasuryCap ID"
    exit 1
fi

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
