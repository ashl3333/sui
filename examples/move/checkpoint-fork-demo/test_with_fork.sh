#!/bin/bash
# Script to run tests with checkpoint fork

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Detect sui binary
if [ -x "../../../target/debug/sui" ]; then
    SUI_BIN="../../../target/debug/sui"
else
    SUI_BIN="sui"
fi

echo "=== Checkpoint Fork Demo: Testing ==="
echo ""

# Check if test state is set up
if [ ! -f .test_checkpoint ]; then
    echo "Error: Test state not set up. Run ./setup_test_state.sh first."
    exit 1
fi

CHECKPOINT=$(cat .test_checkpoint)
USER1=$(cat .test_user1)
COIN_ID=$(cat .test_coin_id)

echo "Test Configuration:"
echo "  Checkpoint: $CHECKPOINT"
echo "  USER1: $USER1"
echo "  Coin ID: $COIN_ID"
echo ""

# Run tests without fork
echo "=== Running tests WITHOUT checkpoint fork ==="
echo "(This uses test-generated state)"
echo ""
"$SUI_BIN" move test
echo ""

# Run tests with fork
echo "=== Running tests WITH checkpoint fork ==="
echo "(This loads real state from checkpoint $CHECKPOINT)"
echo ""
"$SUI_BIN" move test \
    --fork-checkpoint "$CHECKPOINT" \
    --fork-rpc-url https://fullnode.testnet.sui.io:443

echo ""
echo "=== Testing Complete ==="
echo ""
echo "Compare the results:"
echo "- Without fork: Uses test-generated objects"
echo "- With fork: Uses real objects from checkpoint $CHECKPOINT"
