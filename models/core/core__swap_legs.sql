{{ config(
    materialized='incremental',
    unique_key='event_id',
    incremental_strategy='delete+insert',
    indexes=[
        {'columns': ['event_id'], 'unique': true},
        {'columns': ['tx_id']},
        {'columns': ['block_height']},
        {'columns': ['day']}
    ]
) }}

{%- if is_incremental() %}
{%- set since_ns = block_timestamp_ns(high_water_block()) %}
{%- endif %}

-- Legs are classified per transaction, so an incremental run takes the new legs, plus the legs
-- already in the table of every transaction with new legs or new affiliate fee events, and classifies
-- them all again.
with new_legs as (
    {%- if is_incremental() %}
    {{ events__swaps_sql(midgard_rows('swap_events', 'block_timestamp > ' ~ since_ns)) }}
    {%- else %}
    {{ events__swaps_sql(source('midgard', 'swap_events')) }}
    {%- endif %}
),

{%- if is_incremental() %}

touched_transactions as (
    select tx_id from new_legs where coalesce(tx_id, '') !~ '^0*$'
    union
    select tx_id from {{ source('midgard', 'affiliate_fee_events') }} where block_timestamp > {{ since_ns }}
),
{%- endif %}

asset_prices as {{ asset_prices_as_of('new_legs') }},

priced as (
    select
        new_legs.*,
        prices.rune_price_usd,
        asset_prices.asset_price,
        asset_prices.asset_price * prices.rune_price_usd as asset_price_usd
    from new_legs
    left join {{ ref('core__rune_price') }} as prices
        on prices.block_height = new_legs.block_height
    left join asset_prices
        on asset_prices.pool = new_legs.pool
        and asset_prices.block_height = new_legs.block_height
),

valued_new as (
    select
        event_id,
        block_height,
        block_time,
        (block_time at time zone 'UTC')::date as day,
        tx_id,
        chain,
        pool,
        direction,
        from_address,
        to_address,
        from_asset,
        from_amount,
        from_amount_e8,
        from_amount * case when from_asset = 'THOR.RUNE' then rune_price_usd else asset_price_usd end as from_amount_usd,
        to_asset,
        to_amount,
        to_amount_e8,
        to_amount * case when to_asset = 'THOR.RUNE' then rune_price_usd else asset_price_usd end as to_amount_usd,
        liquidity_fee,
        liquidity_fee_e8,
        liquidity_fee * rune_price_usd as liquidity_fee_usd,
        swap_slip_bps,
        {{ units('swap_volume_e8') }} as swap_volume,
        swap_volume_e8,
        {{ units('swap_volume_e8') }} * rune_price_usd as swap_volume_usd,
        is_streaming,
        streaming_count,
        streaming_quantity,
        asset_price_usd,
        rune_price_usd,
        tx_type,
        memo,
        is_internal
    from (
        select
            *,
            -- Midgard's volume measure: the RUNE side of the leg, fee included.
            case
                when direction like 'rune_to_%' then from_amount_e8
                when direction like '%_to_rune' then to_amount_e8 + liquidity_fee_e8
                else 0
            end as swap_volume_e8,
            -- Swaps THORNode makes itself rather than for a user transaction: no transaction id, or the
            -- memo of a protocol swap (affiliate fees converted to a preferred asset, stable reserve operations).
            coalesce(tx_id, '') ~ '^0*$'
                or coalesce(memo, '') like 'THOR-PREFERRED-ASSET-%'
                or coalesce(memo, '') like 'stable-reserve-%' as is_internal
        from priced
    ) as legs
),

valued as (
    select * from valued_new
    {%- if is_incremental() %}

    union all

    select
        event_id, block_height, block_time, day, tx_id, chain, pool, direction, from_address, to_address,
        from_asset, from_amount, from_amount_e8, from_amount_usd, to_asset, to_amount, to_amount_e8,
        to_amount_usd, liquidity_fee, liquidity_fee_e8, liquidity_fee_usd, swap_slip_bps, swap_volume,
        swap_volume_e8, swap_volume_usd, is_streaming, streaming_count, streaming_quantity, asset_price_usd,
        rune_price_usd, tx_type, memo, leg_type = 'internal' as is_internal
    from {{ this }}
    where tx_id in (select tx_id from touched_transactions)
    {%- endif %}
),

fee_events as (
    select
        event_id,
        tx_id,
        asset,
        fee_amt
    from {{ source('midgard', 'affiliate_fee_events') }}
    {%- if is_incremental() %}
    where tx_id in (select tx_id from touched_transactions)
    {%- endif %}
),

first_fee_event as (
    select coalesce(
        (
            select event_id
            from {{ source('midgard', 'affiliate_fee_events') }}
            order by block_timestamp, event_id
            limit 1
        ),
        9223372036854775807
    ) as event_id
),

-- Since affiliate fee events exist, a fee taken in an asset other than RUNE is swapped to RUNE in a
-- leg of the same transaction that sells exactly the fee amount. Legs and events are paired one to one.
event_fee_legs as (
    select legs.event_id
    from (
        select
            event_id,
            tx_id,
            from_asset,
            from_amount_e8,
            row_number() over (partition by tx_id, from_asset, from_amount_e8 order by event_id) as pair_rank
        from valued
        where not is_internal
            and to_asset = 'THOR.RUNE'
    ) as legs
    inner join (
        select
            tx_id,
            asset,
            fee_amt,
            row_number() over (partition by tx_id, asset, fee_amt order by event_id) as pair_rank
        from fee_events
        where asset <> 'THOR.RUNE'
    ) as fees
        on fees.tx_id = legs.tx_id
        and fees.asset = legs.from_asset
        and fees.fee_amt = legs.from_amount_e8
        and fees.pair_rank = legs.pair_rank
),

-- Before affiliate fee events exist, the fee is skimmed from the input: floor(bps × input / 10000) of
-- the input asset is swapped to RUNE in a separate, non-streaming leg of the same transaction, and the
-- user's swap gets the rest. The memo carries a single affiliate and its basis points. Inputs deposited
-- on THORChain itself (RUNE, synths, trade assets) never had a fee leg.
memo_fee_swaps as (
    select
        tx_id,
        from_asset,
        case when bps_field ~ '^\d{1,5}$' then bps_field::bigint end as bps
    from (
        select
            tx_id,
            (array_agg(from_asset order by event_id))[1] as from_asset,
            (array_agg({{ swap_memo_field('memo', 6) }} order by event_id))[1] as bps_field
        from valued
        where not is_internal
            and event_id < (select event_id from first_fee_event)
            and not exists (select 1 from fee_events where fee_events.tx_id = valued.tx_id)
        group by tx_id
    ) as swaps
),

memo_fee_candidates as (
    select
        legs.event_id,
        legs.tx_id,
        legs.from_amount_e8,
        coalesce(legs.streaming_quantity, 0) <= 1 as is_single,
        swaps.bps,
        sum(legs.from_amount_e8) over (partition by legs.tx_id) as input_e8,
        bool_or(coalesce(legs.streaming_quantity, 0) > 1) over (partition by legs.tx_id) as is_streaming_swap
    from valued as legs
    inner join memo_fee_swaps as swaps
        on swaps.tx_id = legs.tx_id
        and swaps.from_asset = legs.from_asset
    where not legs.is_internal
        and swaps.from_asset <> 'THOR.RUNE'
        and swaps.from_asset not like '%/%'
        and swaps.from_asset not like '%~%'
        and swaps.bps > 0
),

memo_fee_legs as (
    select event_id
    from (
        select
            event_id,
            row_number() over (partition by tx_id order by from_amount_e8, event_id) as candidate_rank
        from memo_fee_candidates
        where is_single
            -- A streaming swap's own legs are all streaming, so its single leg is the fee. Otherwise the
            -- fee leg is the one that is exactly the skimmed share of the input (±1 for rounding).
            and (is_streaming_swap or abs(from_amount_e8 - floor(bps * input_e8 / 10000.0)) <= 1)
    ) as candidates
    where candidate_rank = 1
),

classified as (
    select
        *,
        case
            when is_internal then 'internal'
            when event_id in (select event_id from event_fee_legs) then 'affiliate_fee'
            when event_id in (select event_id from memo_fee_legs) then 'affiliate_fee'
            else 'user'
        end as leg_type
    from valued
)

select
    event_id,
    block_height,
    block_time,
    day,
    tx_id,
    chain,
    pool,
    direction,
    leg_type,
    from_address,
    to_address,
    from_asset,
    from_amount,
    from_amount_e8,
    from_amount_usd,
    to_asset,
    to_amount,
    to_amount_e8,
    to_amount_usd,
    liquidity_fee,
    liquidity_fee_e8,
    liquidity_fee_usd,
    swap_slip_bps,
    swap_volume,
    swap_volume_e8,
    swap_volume_usd,
    is_streaming,
    streaming_count,
    streaming_quantity,
    asset_price_usd,
    rune_price_usd,
    tx_type,
    memo
from classified
