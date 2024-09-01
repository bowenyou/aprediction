module aprediction::game {
    use std::signer;
    use std::vector;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use aptos_std::pool_u64_unbound::{Self, Pool};
    use aptos_std::smart_vector::{Self, SmartVector};

    use switchboard::aggregator;
    use switchboard::math::{Self, SwitchboardDecimal};

    const ADMIN: address = @default_admin;
    const FEE_ADDRESS: address = @fee_admin;
    const ORACLE_ADDRESS: address =
        @0xb8f20223af69dcbc33d29e8555e46d031915fc38cb1a4fff5d5167a1e08e8367;

    const ROUND_DURATION: u64 = 300;
    const ROUND_BUFFER: u64 = 30;
    const FEE_BPS: u64 = 5_u64;

    const E_NOT_ADMIN: u64 = 1;
    const E_GENESIS_NOT_STARTED: u64 = 2;
    const E_GENESIS_NOT_LOCKED: u64 = 3;
    const E_GENESIS_ONLY_ONCE: u64 = 4;
    const E_PREV_ROUND_NOT_ENDED: u64 = 5;
    const E_START_TOO_EARLY: u64 = 6;
    const E_ROUND_NOT_STARTED: u64 = 7;
    const E_LOCK_TOO_EARLY: u64 = 8;
    const E_LOCK_TOO_LATE: u64 = 9;
    const E_ROUND_NOT_LOCKED: u64 = 10;
    const E_END_TOO_EARLY: u64 = 11;
    const E_END_TOO_LATE: u64 = 12;
    const E_INVALID_ROUND_ID: u64 = 13;
    const E_CANNOT_BET_ROUND: u64 = 14;
    const E_ALREADY_BET_ROUND: u64 = 15;
    const E_ROUND_NOT_FINALIZED: u64 = 16;

    struct Round has store {
        round_id: u64,
        lock_price: SwitchboardDecimal,
        end_price: SwitchboardDecimal,
        start_time: u64,
        lock_time: u64,
        end_time: u64,
        up_pool: Pool,
        down_pool: Pool,
        finalized: bool,
    }

    struct RoundData has key, store {
        current_round: u64,
        genesis_lock: bool,
        genesis_start: bool,
        rounds: SmartVector<Round>,
        vault: Coin<AptosCoin>,
    }

    public entry fun initialize(admin: &signer) {
        assert!(signer::address_of(admin) == ADMIN, E_NOT_ADMIN);
        let rounds = smart_vector::new<Round>();

        move_to(
            admin,
            RoundData {
                current_round: 0,
                genesis_lock: false,
                genesis_start: false,
                rounds,
                vault: coin::zero<AptosCoin>(),
            },
        );
    }

    fun start_round(round_data: &mut RoundData, round_id: u64) {
        let now = timestamp::now_seconds();
        let round = Round {
            round_id,
            lock_price: math::zero(),
            end_price: math::zero(),
            start_time: now,
            lock_time: now + ROUND_DURATION,
            end_time: now + (2_u64 * ROUND_DURATION),
            up_pool: pool_u64_unbound::new(),
            down_pool: pool_u64_unbound::new(),
            finalized: false,
        };

        smart_vector::push_back(&mut round_data.rounds, round);

        // emit event
    }

    fun safe_start_round(round_data: &mut RoundData, round_id: u64) {
        assert!(round_data.genesis_start, E_GENESIS_NOT_STARTED);

        let past_round = smart_vector::borrow(&round_data.rounds, round_id - 2);
        assert!(past_round.end_time != 0, E_PREV_ROUND_NOT_ENDED);

        let now = timestamp::now_seconds();
        assert!(now >= past_round.end_time, E_START_TOO_EARLY);

        start_round(round_data, round_id);

    }

    fun safe_lock_round(
        round_data: &mut RoundData, round_id: u64, price: SwitchboardDecimal
    ) {
        let round = smart_vector::borrow_mut(&mut round_data.rounds, round_id);
        assert!(round.start_time != 0, E_ROUND_NOT_STARTED);

        let now = timestamp::now_seconds();
        assert!(now >= round.lock_time, E_LOCK_TOO_EARLY);
        assert!(now <= round.lock_time + ROUND_BUFFER, E_LOCK_TOO_LATE);

        round.end_time = now + ROUND_DURATION;
        round.lock_price = price;

        // emit event
    }

    fun safe_end_round(
        round_data: &mut RoundData, round_id: u64, price: SwitchboardDecimal
    ) {
        let round = smart_vector::borrow_mut(&mut round_data.rounds, round_id);
        assert!(round.lock_time != 0, E_ROUND_NOT_LOCKED);

        let now = timestamp::now_seconds();
        assert!(now >= round.end_time, E_END_TOO_EARLY);
        assert!(now <= round.end_time + ROUND_BUFFER, E_END_TOO_LATE);

        round.end_price = price;
        round.finalized = true;

        // emit event
    }

    fun calculate_rewards(round_data: &mut RoundData, round_id: u64) {
        let round = smart_vector::borrow_mut(&mut round_data.rounds, round_id);

        let up_amount = pool_u64_unbound::total_coins(&round.up_pool);
        let down_amount = pool_u64_unbound::total_coins(&round.down_pool);
        let total_amount = up_amount + down_amount;
        let fee = (total_amount * FEE_BPS) / 10_000_u64;

        if (math::lt(&round.lock_price, &round.end_price)) {
            pool_u64_unbound::update_total_coins(&mut round.up_pool, total_amount - fee);
            pool_u64_unbound::update_total_coins(&mut round.down_pool, 0);
        } else if (math::gt(&round.lock_price, &round.end_price)) {
            pool_u64_unbound::update_total_coins(&mut round.down_pool, total_amount - fee);
            pool_u64_unbound::update_total_coins(&mut round.up_pool, 0);
        };

        if (!math::equals(&round.lock_price, &round.end_price)) {
            let fee_coin = coin::extract<AptosCoin>(&mut round_data.vault, fee);
            coin::deposit<AptosCoin>(@fee_admin, fee_coin);
        };

    }

    public entry fun execute_round(admin: &signer) acquires RoundData {
        assert!(signer::address_of(admin) == ADMIN, E_NOT_ADMIN);

        let round_data = borrow_global_mut<RoundData>(@aprediction);
        assert!(round_data.genesis_start, E_GENESIS_NOT_STARTED);
        assert!(round_data.genesis_lock, E_GENESIS_NOT_LOCKED);

        let price = aggregator::latest_value(ORACLE_ADDRESS);

        let current_round = round_data.current_round;
        safe_lock_round(round_data, current_round, price);
        safe_end_round(round_data, current_round - 1, price);
        calculate_rewards(round_data, current_round - 1);

        current_round = current_round + 1;
        round_data.current_round = current_round;
        safe_start_round(round_data, current_round);

    }

    public entry fun genesis_start_round(admin: &signer) acquires RoundData {
        assert!(signer::address_of(admin) == ADMIN, E_NOT_ADMIN);

        let round_data = borrow_global_mut<RoundData>(@aprediction);
        assert!(!round_data.genesis_start, E_GENESIS_ONLY_ONCE);

        let current_round = round_data.current_round + 1;
        start_round(round_data, current_round);
        round_data.current_round = current_round;
        round_data.genesis_start = true;

    }

    public entry fun genesis_lock_round(admin: &signer) acquires RoundData {
        assert!(signer::address_of(admin) == ADMIN, E_NOT_ADMIN);

        let round_data = borrow_global_mut<RoundData>(@aprediction);
        assert!(round_data.genesis_start, E_GENESIS_NOT_STARTED);
        assert!(!round_data.genesis_lock, E_GENESIS_ONLY_ONCE);

        let price = aggregator::latest_value(ORACLE_ADDRESS);

        let current_round = round_data.current_round;
        safe_lock_round(round_data, current_round, price);
        current_round = round_data.current_round + 1;
        round_data.current_round = current_round;
        start_round(round_data, current_round);
        round_data.genesis_lock = true;

    }

    public entry fun bet(
        player: &signer, round_id: u64, direction: bool, amount: u64
    ) acquires RoundData {
        let round_data = borrow_global_mut<RoundData>(@aprediction);
        assert!(round_id < round_data.current_round, E_INVALID_ROUND_ID);

        let round = smart_vector::borrow_mut(&mut round_data.rounds, round_id);
        let now = timestamp::now_seconds();
        assert!(
            round.start_time != 0
            && round.lock_time != 0
            && now > round.start_time
            && now < round.lock_time,
            E_CANNOT_BET_ROUND,
        );

        let player_address = signer::address_of(player);
        let up_shares = pool_u64_unbound::shares(&round.up_pool, player_address);
        let down_shares = pool_u64_unbound::shares(&round.down_pool, player_address);
        assert!(up_shares == 0 && down_shares == 0, E_ALREADY_BET_ROUND);

        let bet_coin = coin::withdraw<AptosCoin>(player, amount);
        coin::merge(&mut round_data.vault, bet_coin);

        if (direction) {
            pool_u64_unbound::buy_in(&mut round.up_pool, player_address, amount);
        } else {
            pool_u64_unbound::buy_in(&mut round.down_pool, player_address, amount);
        }

        // emit event
    }

    fun round_payout(
        player: &signer, round_data: &mut RoundData, round_id: u64
    ): u64 {
        assert!(round_id < round_data.current_round, E_INVALID_ROUND_ID);

        let round = smart_vector::borrow_mut(&mut round_data.rounds, round_id);
        assert!(round.finalized, E_ROUND_NOT_FINALIZED);

        let player_address = signer::address_of(player);
        let up_shares = pool_u64_unbound::shares(&round.up_pool, player_address);
        let down_shares = pool_u64_unbound::shares(&round.down_pool, player_address);

        let up_out =
            pool_u64_unbound::redeem_shares(&mut round.up_pool, player_address, up_shares);
        let down_out =
            pool_u64_unbound::redeem_shares(
                &mut round.down_pool, player_address, down_shares
            );

        up_out + down_out
    }

    public entry fun claim_rounds(player: &signer, round_ids: vector<u64>) acquires RoundData {

        let round_data = borrow_global_mut<RoundData>(@aprediction);

        let amount_claim = 0;
        let n = vector::length(&round_ids);

        for (i in 0..n) {
            amount_claim = amount_claim
                + round_payout(player, round_data, vector::pop_back(&mut round_ids));
        };

        let claim_coin = coin::extract<AptosCoin>(&mut round_data.vault, amount_claim);
        coin::deposit(signer::address_of(player), claim_coin);

        // emit event

    }
}
