// Copyright 2019-2022 SwiftNFT Systems
// SPDX-License-Identifier: Apache-2.0
module market::market_event {
    use sui::object::ID;
    use sui::event;
    use std::ascii::String;

    friend market::market;

    struct MarketCreatedEvent has copy, drop {
        market_id: ID,
        owner: address,
    }

    struct ListedEvent has copy, drop {
        id: ID,
        operator: address,
        price: u64,
        inscription_amount: u64
    }

    struct BuyEvent has copy, drop {
        id: ID,
        from: address,
        to: address,
        price: u64,
        per_price: u64,
    }

    struct CollectionWithdrawalEvent has copy, drop {
        collection_id: ID,
        from: address,
        to: address,
        nft_type: String,
        ft_type: String,
        price: u64,
    }

    struct DeListedEvent has copy, drop {
        id: ID,
        operator: address,
        price: u64,

    }

    struct ModifyPriceEvent has copy, drop {
        id: ID,
        operator: address,
        price: u64,
    }

    struct FloorPriceEvent has copy, drop {
        /// The price of mist
        price: vector<u64>,
        /// The seller of mist
        seller: vector<address>,
        /// The ID of the mist
        object_id: vector<ID>,
        /// The price per mist
        unit_price: vector<u64>,
        /// the amp per mist
        amt: vector<u64>,
        /// the lock price
        acc: vector<u64>
    }

    struct ListingInfoEvent has copy, drop {
        id: ID
    }

    public(friend) fun market_created_event(market_id: ID, owner: address) {
        event::emit(MarketCreatedEvent {
            market_id,
            owner
        })
    }

    public(friend) fun list_event(id: ID, operator: address, price: u64, inscription_amount: u64) {
        event::emit(ListedEvent {
            id,
            operator,
            price,
            inscription_amount
        })
    }

    public(friend) fun buy_event(id: ID, from: address, to: address, price: u64, per_price: u64) {
        event::emit(BuyEvent {
            id,
            from,
            to,
            price,
            per_price
        })
    }

    public(friend) fun collection_withdrawal(collection_id: ID, from: address, to: address, nft_type: String, ft_type: String, price: u64) {
        event::emit(CollectionWithdrawalEvent {
            collection_id,
            from,
            to,
            nft_type,
            ft_type,
            price
        })
    }

    public(friend) fun delisted_event( id: ID, operator: address, price: u64) {
        event::emit(DeListedEvent {
            id,
            operator,
            price,
        })
    }

    public(friend) fun modify_price_event(id: ID, operator: address, price: u64) {
        event::emit(ModifyPriceEvent {
            id,
            operator,
            price
        })
    }

    public(friend) fun floor_price_event(price: vector<u64>,
                                         seller: vector<address>,
                                         object_id: vector<ID>,
                                         unit_price: vector<u64>,
                                         amt: vector<u64>,
                                         acc: vector<u64>

    ){
        event::emit(FloorPriceEvent {
            price,
            seller,
            object_id,
            unit_price,
            amt,
            acc
        })
    }

    public(friend) fun listing_info_event(id: ID){
        event::emit(ListingInfoEvent{
            id
        })
    }

}
