// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A simple demo coin module for checkpoint fork testing
module checkpoint_fork_demo::demo_coin {
    use sui::coin::{Self, Coin, TreasuryCap};

    /// One-time witness for the coin
    public struct DEMO_COIN has drop {}

    /// Initialize the coin with a treasury cap
    /// Note: Using deprecated coin::create_currency for simplicity in this demo
    #[allow(deprecated_usage)]
    fun init(witness: DEMO_COIN, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            8, // decimals
            b"DEMO",
            b"Demo Coin",
            b"A demo coin for checkpoint fork testing",
            option::none(),
            ctx
        );

        // Transfer the treasury cap to the sender
        transfer::public_transfer(treasury, ctx.sender());

        // Freeze the metadata so it can't be changed
        transfer::public_freeze_object(metadata);
    }

    /// Mint new coins (only callable by treasury cap holder)
    public fun mint(
        treasury: &mut TreasuryCap<DEMO_COIN>,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<DEMO_COIN> {
        coin::mint(treasury, amount, ctx)
    }

    /// Burn coins
    public fun burn(
        treasury: &mut TreasuryCap<DEMO_COIN>,
        coin: Coin<DEMO_COIN>
    ) {
        coin::burn(treasury, coin);
    }

    #[test_only]
    /// Initialize for testing
    public fun init_for_testing(ctx: &mut TxContext) {
        init(DEMO_COIN {}, ctx);
    }
}
