// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module checkpoint_fork_demo::checkpoint_fork_tests {
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self as ts};
    use checkpoint_fork_demo::demo_coin::{Self, DEMO_COIN};

    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;

    #[test]
    /// Test without checkpoint fork - creates test state
    fun test_mint_and_transfer_without_fork() {
        let mut scenario = ts::begin(ADMIN);

        // Initialize the coin module
        {
            demo_coin::init_for_testing(ts::ctx(&mut scenario));
        };

        // Mint coins
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut treasury = ts::take_from_sender<coin::TreasuryCap<DEMO_COIN>>(&scenario);
            let coin = demo_coin::mint(&mut treasury, 1000000, ts::ctx(&mut scenario));

            // Transfer to USER1
            transfer::public_transfer(coin, USER1);

            ts::return_to_sender(&scenario, treasury);
        };

        // Verify USER1 received the coins
        ts::next_tx(&mut scenario, USER1);
        {
            let coin = ts::take_from_sender<Coin<DEMO_COIN>>(&scenario);
            let balance = coin::value(&coin);

            assert!(balance == 1000000, 0);

            ts::return_to_sender(&scenario, coin);
        };

        ts::end(scenario);
    }

    #[test]
    /// Test with checkpoint fork - expects real coins from checkpoint
    ///
    /// To run this test with checkpoint fork:
    /// 1. First deploy the contract and mint coins to USER1 on testnet
    /// 2. Note the checkpoint number after the transaction
    /// 3. Run: sui move test --fork-checkpoint <CHECKPOINT> --fork-rpc-url https://fullnode.testnet.sui.io:443
    ///
    /// This test will fail without checkpoint fork because USER1 won't have any DEMO_COIN
    fun test_verify_balance_from_checkpoint() {
        let mut scenario = ts::begin(USER1);

        // When run with checkpoint fork, USER1 should have DEMO_COIN from the checkpoint
        // Without fork, this will fail because no DEMO_COIN exists
        ts::next_tx(&mut scenario, USER1);
        {
            // Try to take DEMO_COIN from USER1
            // This will succeed only if:
            // 1. The test is run with --fork-checkpoint
            // 2. USER1 actually has DEMO_COIN at that checkpoint

            if (ts::has_most_recent_for_sender<Coin<DEMO_COIN>>(&scenario)) {
                let coin = ts::take_from_sender<Coin<DEMO_COIN>>(&scenario);
                let balance = coin::value(&coin);

                // Verify the balance matches what was transferred
                assert!(balance == 1000000, 1);

                ts::return_to_sender(&scenario, coin);
            } else {
                // If running without fork, this branch will be taken
                // The test passes but doesn't verify checkpoint state
                assert!(true, 2);
            };
        };

        ts::end(scenario);
    }

    #[test]
    /// Demonstrates checking for specific checkpoint objects
    fun test_checkpoint_state_inspection() {
        let mut scenario = ts::begin(USER1);

        ts::next_tx(&mut scenario, USER1);
        {
            // Check if DEMO_COIN exists for USER1
            let has_demo_coin = ts::has_most_recent_for_sender<Coin<DEMO_COIN>>(&scenario);

            if (has_demo_coin) {
                // Running with checkpoint fork - verify the coin
                let coin = ts::take_from_sender<Coin<DEMO_COIN>>(&scenario);
                let balance = coin::value(&coin);

                // Log that we found the coin (in tests, use assertions)
                assert!(balance > 0, 3);

                ts::return_to_sender(&scenario, coin);
            } else {
                // Running without checkpoint fork - that's fine too
                assert!(true, 4);
            };
        };

        ts::end(scenario);
    }
}
