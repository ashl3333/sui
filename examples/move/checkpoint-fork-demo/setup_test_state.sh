#!/bin/bash
# Script to mint coins and transfer to test address

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Detect sui binary
if [ -x "../../../target/debug/sui" ]; then
    SUI_BIN="../../../target/debug/sui"
else
    SUI_BIN="sui"
fi

echo "=== Setting Up Test State ==="
echo ""

# Check if package is deployed
if [ ! -f .package_id ]; then
    echo "Error: Package not deployed. Run ./deploy.sh first."
    exit 1
fi

PACKAGE_ID=$(cat .package_id)
TREASURY_ID=$(cat .treasury_id)

echo "Package ID: $PACKAGE_ID"
echo "TreasuryCap ID: $TREASURY_ID"
echo ""

# Define USER1 address (you can change this to any address)
USER1="0x0000000000000000000000000000000000000000000000000000000000000001"
echo "USER1 address: $USER1"
echo ""

# Mint coins using the treasury cap
echo "Minting 1,000,000 DEMO tokens..."
MINT_OUTPUT=$("$SUI_BIN" client call \
    --package "$PACKAGE_ID" \
    --module demo_coin \
    --function mint \
    --args "$TREASURY_ID" 1000000 \
    --gas-budget 10000000 \
    --json 2>&1)

# Extract the minted coin object ID and checkpoint using Python
MINT_PARSED=$(python3 -c "
import json
import sys

output = '''$MINT_OUTPUT'''

try:
    data = json.loads(output)

    # Extract coin ID (created object that's not the treasury)
    coin_id = None
    if 'objectChanges' in data:
        for change in data['objectChanges']:
            if change.get('type') == 'created':
                obj_id = change.get('objectId')
                if obj_id != '$TREASURY_ID':
                    coin_id = obj_id
                    break

    # Extract checkpoint
    checkpoint = data.get('checkpoint', '')

    if coin_id and checkpoint:
        print(f'{coin_id}|{checkpoint}')
    else:
        print('ERROR|ERROR', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)

if [[ "$MINT_PARSED" == ERROR* ]]; then
    echo "Error: Failed to parse mint transaction output"
    exit 1
fi

COIN_ID=$(echo "$MINT_PARSED" | cut -d'|' -f1)
MINT_CHECKPOINT=$(echo "$MINT_PARSED" | cut -d'|' -f2)

echo "Minted Coin ID: $COIN_ID"
echo "Checkpoint after minting: $MINT_CHECKPOINT"
echo ""

# Transfer the coin to USER1
echo "Transferring coin to USER1..."
TRANSFER_OUTPUT=$("$SUI_BIN" client transfer \
    --to "$USER1" \
    --object-id "$COIN_ID" \
    --gas-budget 10000000 \
    --json 2>&1)

# Get checkpoint from the transfer transaction
CHECKPOINT=$(python3 -c "
import json
import sys

output = '''$TRANSFER_OUTPUT'''

try:
    data = json.loads(output)
    checkpoint = data.get('checkpoint', '')

    if checkpoint:
        print(checkpoint)
    else:
        print('ERROR', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)

if [[ "$CHECKPOINT" == ERROR* ]]; then
    echo "Error: Failed to parse transfer transaction output"
    exit 1
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "USER1 address: $USER1"
echo "Coin ID: $COIN_ID"
echo "Checkpoint: $CHECKPOINT"
echo ""
echo "Save this information:"
echo "  export TEST_CHECKPOINT=$CHECKPOINT"
echo "  export TEST_USER1=$USER1"
echo ""
echo "To run tests with checkpoint fork:"
echo "  sui move test --fork-checkpoint $CHECKPOINT --fork-rpc-url https://fullnode.testnet.sui.io:443"
echo ""

# Save test info
echo "$CHECKPOINT" > .test_checkpoint
echo "$USER1" > .test_user1
echo "$COIN_ID" > .test_coin_id

echo "Test information saved to:"
echo "  .test_checkpoint"
echo "  .test_user1"
echo "  .test_coin_id"
