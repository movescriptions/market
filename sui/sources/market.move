// Copyright 2023-2025 MRC20.APP Systems
// SPDX-License-Identifier: Apache-2.0
module market::market {
    use std::ascii;
    use std::ascii::{String, string};
    use sui::object::{Self, ID, UID};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::dynamic_object_field as dof;
    use sui::pay;
    use sui::package;
    use std::vector;
    use market::market_event::{floor_price_event, listing_info_event, burn_floor_event};
    use sui::balance;
    use sui::balance::Balance;
    use sui::clock::timestamp_ms;
    use smartinscription::movescription::{Movescription, tick, amount, inject_sui, do_burn, TickRecord, acc};
    use sui::clock::{Clock};
    use sui::dynamic_field;
    use market::critbit::{CritbitTree, find_leaf};
    use market::critbit;
    use market::market_event;
    use sui::table;
    use sui::table::Table;
    use sui::table_vec;
    use sui::table_vec::TableVec;
    use sui::transfer::public_transfer;

    // One-Time-Witness for the module.
    struct MARKET has drop {}

    const VERSION: u64 = 2;

    const MAX_TICK_LENGTH: u64 = 32;
    const MIN_TICK_LENGTH: u64 = 4;

    const BURN_FEE_RATIO: u64 = 125;
    const COMMUNITY_FEE_RATIO: u64 = 250;
    const LOCK_FEE_RATIO: u64 = 125;
    const MARKET_FEE_RATIO: u64 = 500;

    const TRADE_FEE_BASE_RATIO: u64 = 1000;
    const BASE_MARKET_FEE: u64 = 20;


    const EWrongVersion: u64 = 0;
    const EDoesNotExist: u64 = 1;
    const ENotAuthOperator: u64 = 2;
    const EInputCoin: u64 = 3;
    const EWrongMarket: u64 = 4;
    const ErrorTickLengthInvaid: u64 = 5;
    const EInsufficientBurnCoin: u64 = 6;
    const EPriceTooLow: u64 = 7;
    const EWrongInscription: u64 = 8;


    /// listing info in the market
    struct Listing has key, store {
        id: UID,
        /// The price of inscription
        price: u64,
        /// The seller of inscription
        seller: address,
        /// The ID of the inscription
        inscription_id: ID,
        /// The price per inscription
        inscription_price: u64,
        /// the amt per inscription
        amt: u64,
        /// the lock sui acc
        acc: u64
    }

    #[allow(unused_field)]
    struct Bid has key, store {
        id: UID,
        /// the bidder address
        bidder: address,
        /// the bidder price
        balance: Balance<SUI>,
        /// the bidder want amt
        amt: u64
    }

    ///Record some important information of the market
    struct Marketplace has key {
        id: UID,
        /// the tick of market
        tick: String,
        /// version of market
        version: u64,
        /// marketplace fee collected by marketplace
        balance: Balance<SUI>,
        /// Amount used for repurchasing flooring
        burn_balance: Balance<SUI>,
        /// Community balance
        community_balance: Balance<SUI>,
        /// marketplace fee  of the marketplace
        fee: u64,
        /// listing cribit tree
        listing: CritbitTree<vector<Listing>>,
        /// bid cribit tree
        bid: CritbitTree<vector<Bid>>,
        /// all listing info
        listing_info: Table<address, ListingInfo>
    }

    struct TradeInfo has key, store {
        id: UID,
        tick: String,
        burn_ratio: u64,
        community_ratio: u64,
        lock_ratio: u64,
        timestamp: u64,
        yesterday_volume: u64,
        today_volume: u64,
        total_volume: u64,
    }

    struct ListingInfo has key, store {
        id: UID,
        listing: Table<ID, bool>
    }

    struct ListingDetail has store, drop {
        /// The ID of the inscription
        inscription_id: ID,
        /// The price per inscription
        unit_price: u64,
        /// the amp per inscription
        amt: u64,
        /// the lock sui acc
        acc: u64
    }

    struct AdminCap has key, store {
        id: UID,
    }

    struct MarketplaceHouse has key {
        id: UID,
        market_info: Table<String, ID>,
        markets: TableVec<String>,
    }

    struct BurnInfo has key, store {
        id: UID,
        tick: String,
        amt: u64,
        cost_sui: u64
    }


    public entry fun createMarket(
        tick: vector<u8>,
        market_house: &mut MarketplaceHouse,
        clock: &Clock,
        ctx: &mut TxContext) {
        let tick_str: String = string(tick);
        let tick_len: u64 = ascii::length(&tick_str);
        assert!(MIN_TICK_LENGTH <= tick_len && tick_len <= MAX_TICK_LENGTH, ErrorTickLengthInvaid);
        let market = Marketplace {
            id: object::new(ctx),
            tick: string(tick),
            version: VERSION,
            balance: balance::zero<SUI>(),
            burn_balance: balance::zero<SUI>(),
            community_balance: balance::zero<SUI>(),
            fee: BASE_MARKET_FEE,
            listing: critbit::new(ctx),
            bid: critbit::new(ctx),
            listing_info: table::new(ctx)
        };
        let trade_info = TradeInfo {
            id: object::new(ctx),
            tick: string(tick),
            burn_ratio: BURN_FEE_RATIO,
            community_ratio: COMMUNITY_FEE_RATIO,
            lock_ratio: LOCK_FEE_RATIO,
            timestamp: timestamp_ms(clock),
            yesterday_volume: 0,
            today_volume: 0,
            total_volume: 0,
        };
        table::add(&mut market_house.market_info, string(tick), object::id(&market));
        table_vec::push_back(&mut market_house.markets, string(tick));
        market_event::market_created_event(object::id(&market), tx_context::sender(ctx));
        dynamic_field::add(&mut market.id, 0u8, trade_info);
        transfer::share_object(market);
    }

    fun init(otw: MARKET, ctx: &mut TxContext) {
        //Initialize the marketplace object and set the marketpalce fee
        let market = Marketplace {
            id: object::new(ctx),
            tick: string(b"MOVE"),
            version: VERSION,
            balance: balance::zero<SUI>(),
            burn_balance: balance::zero<SUI>(),
            community_balance: balance::zero<SUI>(),
            fee: BASE_MARKET_FEE,
            listing: critbit::new(ctx),
            bid: critbit::new(ctx),
            listing_info: table::new(ctx)
        };
        let market_info = table::new<String, ID>(ctx);
        let trade_info = TradeInfo {
            id: object::new(ctx),
            tick: string(b"MOVE"),
            burn_ratio: BURN_FEE_RATIO,
            community_ratio: COMMUNITY_FEE_RATIO,
            lock_ratio: LOCK_FEE_RATIO,
            timestamp: 0,
            yesterday_volume: 0,
            today_volume: 0,
            total_volume: 0,
        };
        table::add(&mut market_info, string(b"MOVE"), object::id(&market));

        let market_house = MarketplaceHouse {
            id: object::new(ctx),
            market_info,
            markets: table_vec::singleton(string(b"MOVE"), ctx)
        };
        // Claim the `Publisher` for the package!
        let publisher = package::claim(otw, ctx);
        transfer::public_transfer(publisher, sender(ctx));
        market_event::market_created_event(object::id(&market), tx_context::sender(ctx));
        dynamic_field::add(&mut market.id, 0u8, trade_info);
        transfer::share_object(market);
        transfer::share_object(market_house);
        transfer::public_transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    ///Listing NFT in the collection
    public entry fun list(
        market: &mut Marketplace,
        inscription: Movescription,
        unit_price: u64,
        ctx: &mut TxContext
    ) {
        assert!(market.tick == tick(&inscription), EWrongMarket);
        assert!(market.version == VERSION, EWrongVersion);
        let inscription_id = object::id(&inscription);
        let inscription_amount = amount(&inscription);
        let inscription_acc = acc(&inscription);
        let price = unit_price * inscription_amount;
        assert!(price > 0, EPriceTooLow);
        let listing = Listing {
            id: object::new(ctx),
            price,
            seller: sender(ctx),
            inscription_id,
            inscription_price: unit_price,
            amt: inscription_amount,
            acc: inscription_acc
        };
        let listing_id = object::id(&listing);
        let (find_price, index) = critbit::find_leaf(&market.listing, unit_price);
        if (find_price) {
            vector::push_back(critbit::borrow_mut_leaf_by_index(&mut market.listing, index), listing);
        }else {
            critbit::insert_leaf(&mut market.listing, unit_price, vector::singleton(listing));
        };
        dof::add(&mut market.id, inscription_id, inscription);

        if (table::contains(&market.listing_info, sender(ctx))) {
            let info = table::borrow_mut(&mut market.listing_info, sender(ctx));
            let listing_detail = ListingDetail {
                inscription_id,
                unit_price,
                amt: inscription_amount,
                acc: inscription_acc
            };
            dynamic_field::add(&mut info.id, listing_id, listing_detail);
            table::add(&mut info.listing, listing_id, true);
        }else {
            let listing_info = table::new<ID, bool>(ctx);
            table::add(&mut listing_info, listing_id, true);
            let info = ListingInfo {
                id: object::new(ctx),
                listing: listing_info
            };
            let listing_detail = ListingDetail {
                inscription_id,
                unit_price,
                amt: inscription_amount,
                acc: inscription_acc
            };
            dynamic_field::add(&mut info.id, listing_id, listing_detail);
            table::add(&mut market.listing_info, sender(ctx), info);
        };
        market_event::list_event(inscription_id, tx_context::sender(ctx), unit_price, inscription_amount);
    }


    // ///Adjusting the price of NFT
    // public entry fun modify_price(
    //     market: &mut Marketplace,
    //     inscription_id: ID,
    //     last_price: u64,
    //     price: u64,
    //     ctx: &TxContext
    // ) {
    //     let listing = borrow_mut_listing(&mut market.listing, last_price, inscription_id);
    //     assert!(listing.seller == sender(ctx), ENotAuthOperator);
    //     listing.price = price;
    //     market_event::modify_price_event(inscription_id, sender(ctx), price);
    // }

    ///Cancel the listing of inscription
    public entry fun delist(
        market: &mut Marketplace,
        inscription_id: ID,
        last_price: u64,
        ctx: &TxContext
    ) {
        //Get the list from the collection

        assert!(market.version == VERSION, EWrongVersion);

        let listing = remove_listing(&mut market.listing, last_price, inscription_id);
        let listing_id = object::id(&listing);
        let Listing {
            id,
            price,
            seller,
            inscription_id,
            inscription_price: _,
            amt: _,
            acc: _
        } = listing;
        object::delete(id);
        //Determine the owner's authority
        assert!(sender(ctx) == seller, ENotAuthOperator);

        let inscription = dof::remove<ID, Movescription>(&mut market.id, inscription_id);
        //emit event
        market_event::delisted_event(inscription_id, seller, price);

        let info = table::borrow_mut(&mut market.listing_info, seller);
        table::remove(&mut info.listing, listing_id);
        if (dynamic_field::exists_(&info.id, listing_id)) {
            let _ss = dynamic_field::remove<ID, ListingDetail>(&mut info.id, listing_id);
        };
        if (table::length(&info.listing) == 0) {
            let ListingInfo {
                id,
                listing: table_info
            } = table::remove(&mut market.listing_info, seller);
            table::destroy_empty(table_info);
            object::delete(id);
        };

        public_transfer(inscription, seller)
    }

    struct BurnWitness has key {
        id: UID,
        inscription_id: ID,
        last_price: u64
    }


    ///purchase
    public fun buy(
        market: &mut Marketplace,
        inscription_id: ID,
        paid: &mut Coin<SUI>,
        last_price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Movescription {
        let trade_info = dynamic_field::borrow_mut<u8, TradeInfo>(&mut market.id, 0u8);
        trade_info.total_volume = trade_info.total_volume + coin::value(paid);
        if (timestamp_ms(clock) - trade_info.timestamp > 86400000) {
            trade_info.today_volume = coin::value(paid);
            trade_info.yesterday_volume = trade_info.today_volume;
            trade_info.timestamp = timestamp_ms(clock);
        }else {
            trade_info.today_volume = trade_info.today_volume + coin::value(paid);
        };
        assert!(market.version == VERSION, EWrongVersion);
        let listing = remove_listing(&mut market.listing, last_price, inscription_id);
        let listing_id = object::id(&listing);
        let Listing {
            id,
            price,
            seller,
            inscription_id,
            inscription_price,
            amt: _,
            acc: _
        } = listing;
        object::delete(id);
        assert!(coin::value(paid) >= price, EInputCoin);

        let trade_fee = price * market.fee / TRADE_FEE_BASE_RATIO;
        let surplus = price - trade_fee;
        let market_fee = trade_fee * MARKET_FEE_RATIO / TRADE_FEE_BASE_RATIO;
        let burn_fee = trade_fee * trade_info.burn_ratio / TRADE_FEE_BASE_RATIO;
        let community_fee = trade_fee * trade_info.community_ratio / TRADE_FEE_BASE_RATIO;
        let lock_fee = trade_fee * trade_info.lock_ratio / TRADE_FEE_BASE_RATIO;

        pay::split_and_transfer(paid, surplus, seller, ctx);
        let market_value = coin::split<SUI>(paid, market_fee, ctx);
        let burn_value = coin::split<SUI>(paid, burn_fee, ctx);
        let community_value = coin::split<SUI>(paid, community_fee, ctx);

        let lock_value = coin::split<SUI>(paid, lock_fee, ctx);

        balance::join(&mut market.balance, coin::into_balance(market_value));
        balance::join(&mut market.burn_balance, coin::into_balance(burn_value));
        balance::join(&mut market.community_balance, coin::into_balance(community_value));

        let info = table::borrow_mut(&mut market.listing_info, seller);
        table::remove(&mut info.listing, listing_id);
        if (dynamic_field::exists_(&info.id, listing_id)) {
            let _ss = dynamic_field::remove<ID, ListingDetail>(&mut info.id, listing_id);
        };
        if (table::length(&info.listing) == 0) {
            let ListingInfo {
                id,
                listing: table_info
            } = table::remove(&mut market.listing_info, seller);
            table::destroy_empty(table_info);
            object::delete(id);
        };

        let inscription = dof::remove<ID, Movescription>(&mut market.id, inscription_id);
        inject_sui(&mut inscription, lock_value);
        market_event::buy_event(inscription_id, seller, sender(ctx), price, inscription_price);
        return inscription
    }

    #[lint_allow(self_transfer)]
    public fun buy_with_check(
        market: &mut Marketplace,
        inscription_id: ID,
        paid: &mut Coin<SUI>,
        last_price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        if (!check_listing_exist(&market.listing, last_price, inscription_id)) {
            return
        };
        let trade_info = dynamic_field::borrow_mut<u8, TradeInfo>(&mut market.id, 0u8);
        trade_info.total_volume = trade_info.total_volume + coin::value(paid);
        if (timestamp_ms(clock) - trade_info.timestamp > 86400000) {
            trade_info.today_volume = coin::value(paid);
            trade_info.yesterday_volume = trade_info.today_volume;
            trade_info.timestamp = timestamp_ms(clock);
        }else {
            trade_info.today_volume = trade_info.today_volume + coin::value(paid);
        };
        assert!(market.version == VERSION, EWrongVersion);
        let listing = remove_listing(&mut market.listing, last_price, inscription_id);
        let listing_id = object::id(&listing);
        let Listing {
            id,
            price,
            seller,
            inscription_id,
            inscription_price,
            amt: _,
            acc: _
        } = listing;
        object::delete(id);
        assert!(coin::value(paid) >= price, EInputCoin);

        let trade_fee = price * market.fee / TRADE_FEE_BASE_RATIO;
        let surplus = price - trade_fee;
        let market_fee = trade_fee * MARKET_FEE_RATIO / TRADE_FEE_BASE_RATIO;
        let burn_fee = trade_fee * trade_info.burn_ratio / TRADE_FEE_BASE_RATIO;
        let community_fee = trade_fee * trade_info.community_ratio / TRADE_FEE_BASE_RATIO;
        let lock_fee = trade_fee * trade_info.lock_ratio / TRADE_FEE_BASE_RATIO;

        pay::split_and_transfer(paid, surplus, seller, ctx);
        let market_value = coin::split<SUI>(paid, market_fee, ctx);
        let burn_value = coin::split<SUI>(paid, burn_fee, ctx);
        let community_value = coin::split<SUI>(paid, community_fee, ctx);

        let lock_value = coin::split<SUI>(paid, lock_fee, ctx);

        balance::join(&mut market.balance, coin::into_balance(market_value));
        balance::join(&mut market.burn_balance, coin::into_balance(burn_value));
        balance::join(&mut market.community_balance, coin::into_balance(community_value));

        let info = table::borrow_mut(&mut market.listing_info, seller);
        table::remove(&mut info.listing, listing_id);
        if (dynamic_field::exists_(&info.id, listing_id)) {
            let _ss = dynamic_field::remove<ID, ListingDetail>(&mut info.id, listing_id);
        };
        if (table::length(&info.listing) == 0) {
            let ListingInfo {
                id,
                listing: table_info
            } = table::remove(&mut market.listing_info, seller);
            table::destroy_empty(table_info);
            object::delete(id);
        };

        let inscription = dof::remove<ID, Movescription>(&mut market.id, inscription_id);
        inject_sui(&mut inscription, lock_value);
        market_event::buy_event(inscription_id, seller, sender(ctx), price, inscription_price);
        public_transfer(inscription, sender(ctx));
        return
    }

    public fun burn_floor_inscription(
        market: &mut Marketplace,
        ctx: &mut TxContext
    ): (Coin<SUI>, BurnWitness) {
        assert!(market.version == VERSION, EWrongVersion);

        let (from, _) = critbit::min_leaf(&market.listing);
        let listing = critbit::borrow_leaf_by_key(&market.listing, from);
        assert!(vector::length(listing) > 0, EDoesNotExist);
        let borrow_listing = vector::borrow(listing, 0);
        assert!(balance::value(&market.burn_balance) >= borrow_listing.price, EInsufficientBurnCoin);
        let burn_witness = BurnWitness {
            id: object::new(ctx),
            inscription_id: borrow_listing.inscription_id,
            last_price: borrow_listing.inscription_price
        };
        dynamic_field::add(&mut burn_witness.id, 0u8, borrow_listing.amt);
        let coin = coin::take(&mut market.burn_balance, borrow_listing.price, ctx);
        // let inscription= buy(market, borrow_listing.inscription_id, &mut coin, borrow_listing.price, clock, ctx);
        return (coin, burn_witness)
    }

    public fun buy_with_burn_witness(
        market: &mut Marketplace,
        burn_witness: BurnWitness,
        ticket_record: &mut TickRecord,
        paid: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let inscription_amt = dynamic_field::remove<u8, u64>(&mut burn_witness.id, 0u8);
        let BurnWitness {
            id,
            inscription_id,
            last_price
        } = burn_witness;
        let cost_sui = coin::value(&paid);
        object::delete(id);
        let inscription = buy(market, inscription_id, &mut paid, last_price, clock, ctx);
        assert!(inscription_amt == amount(&inscription), EWrongInscription);
        if (!dynamic_field::exists_(&market.id, b"burn_info")) {
            dynamic_field::add(&mut market.id, b"burn_info", BurnInfo {
                id: object::new(ctx),
                tick: market.tick,
                amt: 0,
                cost_sui: 0
            })
        }else {
            let burn_info = dynamic_field::borrow_mut<vector<u8>, BurnInfo>(&mut market.id, b"burn_info");
            burn_info.cost_sui = burn_info.cost_sui + cost_sui;
            burn_info.amt = burn_info.amt + amount(&inscription)
        };
        burn_floor_event(inscription_id, sender(ctx), amount(&inscription), acc(&inscription), cost_sui);
        let acc_coin = do_burn(ticket_record, inscription, ctx);
        coin::join(&mut paid, acc_coin);
        balance::join(&mut market.burn_balance, coin::into_balance(paid));
    }


    public entry fun withdraw_profits(
        _admin: &AdminCap,
        market: &mut Marketplace,
        receiver: address,
        ctx: &mut TxContext
    ) {
        assert!(market.version == VERSION, EWrongVersion);
        let balances = balance::value(&market.balance);
        let coins = balance::split(&mut market.balance, balances);
        transfer::public_transfer(coin::from_balance(coins, ctx), receiver);
    }


    public entry fun update_market_fee(
        _admin: &AdminCap,
        market: &mut Marketplace,
        fee: u64,
        _ctx: &mut TxContext
    ) {
        assert!(market.version == VERSION, EWrongVersion);
        market.fee = fee
    }

    public entry fun change_admin(
        admin: AdminCap,
        receiver: address,
    ) {
        transfer::public_transfer(admin, receiver);
    }

    public entry fun migrate_marketplace(marketplace: &mut Marketplace) {
        assert!(marketplace.version <= VERSION, EWrongVersion);
        marketplace.version = VERSION;
    }

    #[allow(unused_function)]
    fun borrow_mut_listing(listings: &mut CritbitTree<vector<Listing>>, price: u64, inscription_id: ID): &mut Listing {
        let price_level = critbit::borrow_mut_leaf_by_key(listings, price);

        let index = 0;
        let listings_count = vector::length(price_level);
        while (listings_count > index) {
            let listing = vector::borrow(price_level, index);
            // on the same price level, we search for the specified NFT
            if (inscription_id == listing.inscription_id) {
                break
            };

            index = index + 1;
        };

        assert!(index < listings_count, EDoesNotExist);
        let listing = vector::borrow_mut(price_level, index);
        listing
    }

    fun check_listing_exist(listings: &CritbitTree<vector<Listing>>, price: u64, inscription_id: ID): bool {
        let (exist, _) = critbit::find_leaf(listings, price);
        if (!exist) {
            return false
        };
        let price_level = critbit::borrow_leaf_by_key(listings, price);

        let index = 0;
        let listings_count = vector::length(price_level);
        while (listings_count > index) {
            let listing = vector::borrow(price_level, index);
            // on the same price level, we search for the specified NFT
            if (inscription_id == listing.inscription_id) {
                break
            };

            index = index + 1;
        };
        if (index >= listings_count) {
            false
        }else {
            true
        }
    }

    fun remove_listing(listings: &mut CritbitTree<vector<Listing>>, price: u64, inscription_id: ID): Listing {
        let price_level = critbit::borrow_mut_leaf_by_key(listings, price);

        let index = 0;
        let listings_count = vector::length(price_level);
        while (listings_count > index) {
            let listing = vector::borrow(price_level, index);
            // on the same price level, we search for the specified NFT
            if (inscription_id == listing.inscription_id) {
                break
            };

            index = index + 1;
        };

        assert!(index < listings_count, EDoesNotExist);

        let listing = vector::remove(price_level, index);
        if (vector::length(price_level) == 0) {
            // to simplify impl, always delete empty price level
            let (find, leaf_index) = find_leaf(listings, price);
            if (find) {
                vector::destroy_empty(critbit::remove_leaf_by_index(listings, leaf_index));
            }
        };

        listing
    }

    public fun floor_listing(market: &Marketplace, from: u64, start: u64): vector<ID> {
        let res = vector<ID>[];
        let price = vector<u64>[];
        let seller = vector<address>[];
        let object_id = vector<ID>[];
        let unit_price = vector<u64>[];
        let amt = vector<u64>[];
        let acc = vector<u64>[];

        let i = 0;
        if (from == 0) {
            (from, _) = critbit::min_leaf(&market.listing);
        };
        let count = start;
        while (i < 50) {
            let listing = critbit::borrow_leaf_by_key(&market.listing, from);
            let listings_count = vector::length(listing);

            while (listings_count > count) {
                let borrow_listing = vector::borrow(listing, count);
                vector::push_back(&mut res, object::id(borrow_listing));
                vector::push_back(&mut price, borrow_listing.price);
                vector::push_back(&mut seller, borrow_listing.seller);
                vector::push_back(&mut object_id, borrow_listing.inscription_id);
                vector::push_back(&mut unit_price, borrow_listing.inscription_price);
                vector::push_back(&mut amt, borrow_listing.amt);
                vector::push_back(&mut acc, borrow_listing.acc);

                count = count + 1;
                i = i + 1;
                if (i >= 50) {
                    floor_price_event(price, seller, object_id, unit_price, amt, acc);
                    return res
                }
            };
            count = 0;
            let (key, index) = critbit::next_leaf(&market.listing, from);
            if (index != 0x8000000000000000) {
                from = key;
            }else {
                floor_price_event(price, seller, object_id, unit_price, amt, acc);
                return res
            }
        };
        floor_price_event(price, seller, object_id, unit_price, amt, acc);
        return res
    }

    public fun listing_info(market: &Marketplace, seller: address): ID {
        let info = table::borrow(&market.listing_info, seller);
        let info_id = object::id(&info.listing);
        listing_info_event(info_id);
        return info_id
    }

    public fun listing_detail(market: &Marketplace, seller: address): ID {
        let info = table::borrow(&market.listing_info, seller);
        let info_id = object::id(info);
        listing_info_event(info_id);
        return info_id
    }
}
