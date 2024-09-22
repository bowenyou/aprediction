module aprediction::game {
    use std::error;
    use std::signer;
    use std::vector;

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::event;
    use aptos_std::pool_u64_unbound::{Self, Pool};
    use aptos_std::smart_vector::{Self, SmartVector};
    use aptos_framework::timestamp;
    use aptos_framework::object;

    use switchboard::aggregator;
    use switchboard::math::{Self, SwitchboardDecimal};

    const ADMIN: address = @default_admin;
    const DEV: address = @dev;
    const FEE_ADDRESS: address = @fee_admin;
    const ORACLE_ADDRESS: address =
        @0x7ac62190ba57b945975146f3d8725430ad3821391070b965b38206fe4cec9fd5;

    const RESOURCE_SEED: vector<u8> = b"APREDICTION";
    const ROUND_DURATION: u64 = 300;
    const ROUND_BUFFER: u64 = 30;
    const FEE_BPS: u64 = 5_u64;

    const E_ALREADY_INITIALIZED: u64 = 0;
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

    #[event]
    struct RoundStartedEvent has drop, store {
        round_id: u64,
    }

    #[event]
    struct RoundLockedEvent has drop, store {
        round_id: u64,
        locked_price: SwitchboardDecimal,
    }

    #[event]
    struct RoundEndedEvent has drop, store {
        round_id: u64,
        end_price: SwitchboardDecimal,
    }

    #[event]
    struct RewardCalculatedEvent has drop, store {
        round_id: u64
    }

    #[event]
    struct BetEvent has drop, store {
        player: address,
        round_id: u64,
        amount: u64,
        direction: bool
    }

    #[event]
    struct ClaimEvent has drop, store {
        player: address,
        claimed_amount: u64,
    }

    struct GameInfo has key {
        extend_ref: object::ExtendRef,
        admin: address,
        fee: address
    }

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

    fun init_module(deployer: &signer) {

        let constructor_ref = object::create_named_object(deployer, RESOURCE_SEED);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let app_signer = object::generate_signer(&constructor_ref);

        move_to(
            &app_signer,
            GameInfo { extend_ref, admin: ADMIN, fee: FEE_ADDRESS },
        );

        let rounds = smart_vector::new<Round>();

        move_to(
            &app_signer,
            RoundData {
                current_round: 0,
                genesis_lock: false,
                genesis_start: false,
                rounds,
                vault: coin::zero<AptosCoin>(),
            },
        );
    }

    fun get_object_address(): address {
        object::create_object_address(&@aprediction, RESOURCE_SEED)
    }

    fun get_object_signer(): signer acquires GameInfo {
        let object_address = get_object_address();
        object::generate_signer_for_extending(
            &borrow_global<GameInfo>(object_address).extend_ref
        )
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

        event::emit(RoundStartedEvent { round_id });
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
        assert!(
            now <= round.lock_time + ROUND_BUFFER,
            E_LOCK_TOO_LATE,
        );

        round.end_time = now + ROUND_DURATION;
        round.lock_price = price;

        event::emit(RoundLockedEvent { round_id, locked_price: price });

    }

    fun safe_end_round(
        round_data: &mut RoundData, round_id: u64, price: SwitchboardDecimal
    ) {
        let round = smart_vector::borrow_mut(&mut round_data.rounds, round_id);
        assert!(round.lock_time != 0, E_ROUND_NOT_LOCKED);

        let now = timestamp::now_seconds();
        assert!(now >= round.end_time, E_END_TOO_EARLY);
        assert!(
            now <= round.end_time + ROUND_BUFFER,
            E_END_TOO_LATE,
        );

        round.end_price = price;
        round.finalized = true;

        event::emit(RoundEndedEvent { round_id, end_price: price });

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

        event::emit(RewardCalculatedEvent { round_id });

    }

    public entry fun execute_round(admin: &signer) acquires GameInfo, RoundData {

        let object_address = signer::address_of(&get_object_signer());
        let game_info = borrow_global<GameInfo>(object_address);
        assert!(signer::address_of(admin) == game_info.admin, E_NOT_ADMIN);

        let round_data = borrow_global_mut<RoundData>(object_address);
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

    public entry fun genesis_start_round(admin: &signer) acquires GameInfo, RoundData {

        let object_address = signer::address_of(&get_object_signer());
        let game_info = borrow_global<GameInfo>(object_address);
        assert!(
            signer::address_of(admin) == game_info.admin,
            E_NOT_ADMIN,
        );

        let round_data = borrow_global_mut<RoundData>(object_address);
        assert!(!round_data.genesis_start, E_GENESIS_ONLY_ONCE);

        let current_round = round_data.current_round;
        start_round(round_data, current_round);
        round_data.genesis_start = true;

    }

    public entry fun genesis_lock_round(admin: &signer) acquires GameInfo, RoundData {

        let object_address = signer::address_of(&get_object_signer());
        let game_info = borrow_global<GameInfo>(object_address);
        assert!(signer::address_of(admin) == game_info.admin, E_NOT_ADMIN);

        let round_data = borrow_global_mut<RoundData>(object_address);
        assert!(round_data.genesis_start, E_GENESIS_NOT_STARTED);
        assert!(!round_data.genesis_lock, E_GENESIS_ONLY_ONCE);

        let price = aggregator::latest_value(ORACLE_ADDRESS);

        let current_round = round_data.current_round;
        safe_lock_round(round_data, current_round, price);
        current_round = current_round + 1;
        round_data.current_round = current_round;
        start_round(round_data, current_round);
        round_data.genesis_lock = true;

    }

    public entry fun bet(player: &signer, direction: bool, amount: u64) acquires GameInfo, RoundData {

        let object_address = signer::address_of(&get_object_signer());
        let game_info = borrow_global<GameInfo>(object_address);

        let round_data = borrow_global_mut<RoundData>(object_address);
        let round_id = round_data.current_round;

        let round = smart_vector::borrow_mut(&mut round_data.rounds, round_id);
        let now = timestamp::now_seconds();
        assert!(
            round.start_time != 0
            && round.lock_time != 0
            && now > round.start_time
            && now < round.lock_time,
            E_CANNOT_BET_ROUND,
        );

        let player_addr = signer::address_of(player);
        let up_shares = pool_u64_unbound::shares(&round.up_pool, player_addr);
        let down_shares = pool_u64_unbound::shares(&round.down_pool, player_addr);
        assert!(
            up_shares == 0 && down_shares == 0,
            E_ALREADY_BET_ROUND,
        );

        let bet_coin = coin::withdraw<AptosCoin>(player, amount);
        coin::merge(&mut round_data.vault, bet_coin);

        if (direction) {
            pool_u64_unbound::buy_in(&mut round.up_pool, player_addr, amount);
        } else {
            pool_u64_unbound::buy_in(&mut round.down_pool, player_addr, amount);
        };

        event::emit(BetEvent { player: player_addr, round_id, amount, direction });

    }

    fun round_payout(
        player_addr: address, round_data: &mut RoundData, round_id: u64
    ): u64 {
        assert!(round_id < round_data.current_round, E_INVALID_ROUND_ID);

        let round = smart_vector::borrow_mut(&mut round_data.rounds, round_id);
        assert!(round.finalized, error::invalid_state(E_ROUND_NOT_FINALIZED));

        let up_shares = pool_u64_unbound::shares(&round.up_pool, player_addr);
        let down_shares = pool_u64_unbound::shares(&round.down_pool, player_addr);

        let up_out = 0;
        let down_out = 0;

        if (up_shares > 0) {
            up_out = pool_u64_unbound::redeem_shares(
                &mut round.up_pool, player_addr, up_shares
            );
        };

        if (down_shares > 0) {
            down_out = pool_u64_unbound::redeem_shares(
                &mut round.down_pool, player_addr, down_shares
            );
        };

        up_out + down_out
    }

    public entry fun claim_rounds(player: &signer, round_ids: vector<u64>) acquires GameInfo, RoundData {

        let object_address = signer::address_of(&get_object_signer());
        let game_info = borrow_global<GameInfo>(object_address);

        let round_data = borrow_global_mut<RoundData>(object_address);

        let amount_claim = 0;
        let n = vector::length(&round_ids);
        let player_addr = signer::address_of(player);

        for (i in 0..n) {
            amount_claim = amount_claim
                + round_payout(player_addr, round_data, vector::pop_back(&mut round_ids));
        };

        let player_addr = signer::address_of(player);
        let claim_coin = coin::extract<AptosCoin>(&mut round_data.vault, amount_claim);
        coin::deposit(player_addr, claim_coin);

        event::emit(ClaimEvent { player: player_addr, claimed_amount: amount_claim });

    }

    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use aptos_framework::genesis;
    #[test_only]
    use aptos_framework::aptos_coin;

    #[test_only]
    public fun initialize_for_test(deployer: &signer) {
        init_module(deployer);
    }

    #[test_only]
    fun setup(aptos_framework: &signer): address acquires GameInfo {
        genesis::setup();
        let admin = account::create_account_for_test(@aprediction);
        let fee = account::create_account_for_test(@fee_admin);
        let oracle = account::create_account_for_test(ORACLE_ADDRESS);
        let (burn, mint) =
            aptos_coin::initialize_for_test_without_aggregator_factory(aptos_framework);
        initialize_for_test(&admin);
        aggregator::new_test(&oracle, 1, 0, false);

        let alice = account::create_account_for_test(@0xA);
        let bob = account::create_account_for_test(@0xB);
        coin::register<AptosCoin>(&alice);
        coin::register<AptosCoin>(&bob);
        coin::register<AptosCoin>(&fee);

        let coins = coin::mint<AptosCoin>(20000, &mint);
        coin::deposit<AptosCoin>(signer::address_of(&alice), coins);

        let coins = coin::mint<AptosCoin>(20000, &mint);
        coin::deposit<AptosCoin>(signer::address_of(&bob), coins);
        coin::destroy_burn_cap<AptosCoin>(burn);
        coin::destroy_mint_cap<AptosCoin>(mint);

        let object_signer = get_object_signer();
        signer::address_of(&object_signer)
    }

    #[test(aptos_framework = @0x1)]
    fun test_init_module(aptos_framework: &signer) acquires GameInfo, RoundData {
        let object_signer = setup(aptos_framework);

        let round_data = borrow_global<RoundData>(object_signer);
        assert!(!round_data.genesis_start, 0);
        assert!(!round_data.genesis_lock, 0);
        assert!(round_data.current_round == 0, 0);
    }

    #[test(aptos_framework = @0x1, admin = @default_admin)]
    #[expected_failure(abort_code = E_GENESIS_NOT_STARTED)]
    fun test_execute_round_before_genesis(
        aptos_framework: &signer, admin: &signer
    ) acquires GameInfo, RoundData {
        let object_signer = setup(aptos_framework);
        execute_round(admin);
    }

    #[test(aptos_framework = @0x1, admin = @default_admin)]
    fun test_genesis_start_round(
        aptos_framework: &signer, admin: &signer
    ) acquires GameInfo, RoundData {

        let object_signer = setup(aptos_framework);
        timestamp::update_global_time_for_test_secs(1);
        genesis_start_round(admin);

        let round_data = borrow_global<RoundData>(object_signer);
        assert!(round_data.genesis_start, 0);
        assert!(!round_data.genesis_lock, 0);
        assert!(round_data.current_round == 0, 0);

        let round = smart_vector::borrow(&round_data.rounds, 0);
        assert!(round.round_id == 0, 0);
        assert!(round.start_time == 1, 0);
        assert!(round.lock_time == 1 + ROUND_DURATION, 0);
        assert!(round.end_time == 1 + 2_u64 * ROUND_DURATION, 0);
    }

    #[test(aptos_framework = @0x1, admin = @default_admin)]
    #[expected_failure(abort_code = E_GENESIS_ONLY_ONCE)]
    fun test_genesis_start_round_twice(
        aptos_framework: &signer, admin: &signer
    ) acquires GameInfo, RoundData {
        setup(aptos_framework);
        genesis_start_round(admin);
        genesis_start_round(admin);
    }

    #[test(aptos_framework = @0x1, admin = @default_admin)]
    #[expected_failure(abort_code = E_GENESIS_NOT_STARTED)]
    fun test_genesis_lock_round_before_start(
        aptos_framework: &signer, admin: &signer
    ) acquires GameInfo, RoundData {
        setup(aptos_framework);
        genesis_lock_round(admin);
    }

    #[test(aptos_framework = @0x1, admin = @default_admin)]
    #[expected_failure(abort_code = E_LOCK_TOO_EARLY)]
    fun test_genesis_lock_too_early(
        aptos_framework: &signer, admin: &signer
    ) acquires GameInfo, RoundData {

        let object_signer = setup(aptos_framework);
        timestamp::update_global_time_for_test_secs(1);
        genesis_start_round(admin);
        genesis_lock_round(admin);
    }

    #[test(aptos_framework = @0x1, admin = @default_admin)]
    fun test_genesis_lock(aptos_framework: &signer, admin: &signer) acquires GameInfo, RoundData {

        let object_signer = setup(aptos_framework);
        timestamp::update_global_time_for_test_secs(1);
        genesis_start_round(admin);
        timestamp::update_global_time_for_test_secs(1 + ROUND_DURATION);
        genesis_lock_round(admin);

        let round_data = borrow_global<RoundData>(object_signer);
        assert!(round_data.genesis_start, 0);
        assert!(round_data.genesis_lock, 0);
        assert!(round_data.current_round == 1, 0);

        let round = smart_vector::borrow(&round_data.rounds, 0);
        assert!(math::gt(&round.lock_price, &math::zero()), 0);
        assert!(math::equals(&round.end_price, &math::zero()), 0);

        let round = smart_vector::borrow(&round_data.rounds, 1);
        assert!(round.round_id == 1, 0);
        assert!(round.start_time == 1 + ROUND_DURATION, 0);
        assert!(round.lock_time == 1 + 2 * ROUND_DURATION, 0);
        assert!(round.end_time == 1 + 3_u64 * ROUND_DURATION, 0);
    }

    #[test(aptos_framework = @0x1, admin = @default_admin)]
    #[expected_failure(abort_code = E_LOCK_TOO_LATE)]
    fun test_genesis_lock_too_late(
        aptos_framework: &signer, admin: &signer
    ) acquires GameInfo, RoundData {

        let object_signer = setup(aptos_framework);
        timestamp::update_global_time_for_test_secs(1);
        genesis_start_round(admin);
        timestamp::update_global_time_for_test_secs(1 + ROUND_DURATION + ROUND_BUFFER + 1);
        genesis_lock_round(admin);
    }

    #[test(aptos_framework = @0x1, admin = @default_admin)]
    fun test_execute_round(aptos_framework: &signer, admin: &signer) acquires GameInfo, RoundData {

        let object_signer = setup(aptos_framework);
        timestamp::update_global_time_for_test_secs(1);
        genesis_start_round(admin);
        timestamp::update_global_time_for_test_secs(1 + ROUND_DURATION);
        genesis_lock_round(admin);
        timestamp::update_global_time_for_test_secs(1 + 2 * ROUND_DURATION + 1);
        execute_round(admin);

        let round_data = borrow_global<RoundData>(object_signer);
        assert!(round_data.current_round == 2, 0);

        let round = smart_vector::borrow(&round_data.rounds, 0);
        assert!(math::gt(&round.lock_price, &math::zero()), 0);
        assert!(math::gt(&round.end_price, &math::zero()), 0);
        assert!(round.finalized, 0);

        let round = smart_vector::borrow(&round_data.rounds, 1);
        assert!(math::gt(&round.lock_price, &math::zero()), 0);
        assert!(math::equals(&round.end_price, &math::zero()), 0);
        assert!(round.end_time == 1 + 3 * ROUND_DURATION + 1, 0);

        let round = smart_vector::borrow(&round_data.rounds, 2);
        assert!(math::equals(&round.lock_price, &math::zero()), 0);
        assert!(math::equals(&round.end_price, &math::zero()), 0);

    }

    #[test(aptos_framework = @0x1, admin = @default_admin, alice = @0xA, bob = @0xB)]
    fun test_bet(
        aptos_framework: &signer, admin: &signer, alice: &signer, bob: &signer
    ) acquires GameInfo, RoundData {

        let object_signer = setup(aptos_framework);
        timestamp::update_global_time_for_test_secs(1);
        genesis_start_round(admin);
        timestamp::update_global_time_for_test_secs(2);

        bet(alice, true, 100);
        bet(bob, false, 150);

        let round_data = borrow_global<RoundData>(object_signer);
        let round = smart_vector::borrow(&round_data.rounds, 0);
        assert!(pool_u64_unbound::total_coins(&round.up_pool) == 100, 0);
        assert!(
            pool_u64_unbound::balance(&round.up_pool, signer::address_of(alice)) > 0, 0
        );
        assert!(pool_u64_unbound::total_coins(&round.down_pool) == 150, 0);
        assert!(
            pool_u64_unbound::balance(&round.down_pool, signer::address_of(bob)) > 0, 0
        );
        assert!(coin::value<AptosCoin>(&round_data.vault) == 250, 0);

    }

    #[test(aptos_framework = @0x1, admin = @default_admin, alice = @0xA)]
    #[expected_failure(abort_code = E_ALREADY_BET_ROUND)]
    fun test_bet_twice(
        aptos_framework: &signer, admin: &signer, alice: &signer
    ) acquires GameInfo, RoundData {

        let object_signer = setup(aptos_framework);
        timestamp::update_global_time_for_test_secs(1);
        genesis_start_round(admin);
        timestamp::update_global_time_for_test_secs(2);

        bet(alice, true, 100);
        bet(alice, true, 100);

    }

    #[test(aptos_framework = @0x1, admin = @default_admin, alice = @0xA)]
    #[expected_failure(abort_code = E_CANNOT_BET_ROUND)]
    fun test_bet_after_lock(
        aptos_framework: &signer, admin: &signer, alice: &signer
    ) acquires GameInfo, RoundData {

        let object_signer = setup(aptos_framework);
        timestamp::update_global_time_for_test_secs(1);
        genesis_start_round(admin);
        timestamp::update_global_time_for_test_secs(1 + ROUND_DURATION);

        bet(alice, true, 100);

    }

    #[test(aptos_framework = @0x1, admin = @default_admin, alice = @0xA, bob = @0xB, oracle = @0x7ac62190ba57b945975146f3d8725430ad3821391070b965b38206fe4cec9fd5)]
    fun test_claim(
        aptos_framework: &signer,
        admin: &signer,
        alice: &signer,
        bob: &signer,
        oracle: &signer
    ) acquires GameInfo, RoundData {

        let object_signer = setup(aptos_framework);
        timestamp::update_global_time_for_test_secs(1);
        genesis_start_round(admin);
        timestamp::update_global_time_for_test_secs(2);

        bet(alice, true, 10000);
        bet(bob, false, 15000);

        timestamp::update_global_time_for_test_secs(1 + ROUND_DURATION);
        genesis_lock_round(admin);
        aggregator::update_value(oracle, 2, 0, false);
        timestamp::update_global_time_for_test_secs(1 + 2 * ROUND_DURATION);

        execute_round(admin);

        let round_data = borrow_global<RoundData>(object_signer);
        let round = smart_vector::borrow(&round_data.rounds, 0);
        assert!(pool_u64_unbound::total_coins(&round.up_pool) == 25000 - 12, 0);
        assert!(
            pool_u64_unbound::shares(&round.up_pool, signer::address_of(alice)) > 0, 0
        );
        assert!(pool_u64_unbound::total_coins(&round.down_pool) == 0, 0);
        assert!(
            pool_u64_unbound::shares(&round.down_pool, signer::address_of(bob)) > 0, 0
        );
        assert!(coin::value<AptosCoin>(&round_data.vault) == 25000 - 12, 0);
        assert!(coin::balance<AptosCoin>(@fee_admin) == 12, 0);

        let round_ids = vector::empty<u64>();
        vector::push_back<u64>(&mut round_ids, 0);

        claim_rounds(alice, round_ids);
        claim_rounds(bob, round_ids);
        assert!(coin::balance<AptosCoin>(signer::address_of(alice)) == 10000 + 25000 - 12, 0);
        assert!(coin::balance<AptosCoin>(signer::address_of(bob)) == 5000, 0);

    }
}
