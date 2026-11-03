{{ config(
    materialized='incremental',
    unique_key='tx_id',
    incremental_strategy='delete+insert',
    indexes=[
        {'columns': ['tx_id'], 'unique': true},
        {'columns': ['day']},
        {'columns': ['end_block_height']},
        {'columns': ['status']}
    ]
) }}

{%- if is_incremental() %}
{%- set last_block = high_water_block('end_block_height') %}
{%- endif %}

-- A user swap is the user legs of one transaction. Affiliate fee legs in the same transaction count
-- towards its swap volume, liquidity fee and leg count only; internal legs belong to no user swap.
-- An incremental run rebuilds the swaps with new legs, affiliate fees or streaming swap results since
-- the last block in the table, and every swap still in progress.
with
{%- if is_incremental() %}
touched_transactions as (
    select tx_id from {{ ref('core__swap_legs') }}
    where block_height > {{ last_block }} and leg_type in ('user', 'affiliate_fee')
    union
    select tx_id from {{ ref('core__affiliate_fees') }}
    where block_height > {{ last_block }}
    union
    select tx_id from {{ source('midgard', 'streaming_swap_details_events') }}
    where block_timestamp > {{ block_timestamp_ns(last_block) }}
    union
    select tx_id from {{ this }}
    where status = 'in_progress'
),
{%- endif %}

swap_legs as (
    select * from {{ ref('core__swap_legs') }}
    where leg_type in ('user', 'affiliate_fee')
    {%- if is_incremental() %}
        and tx_id in (select tx_id from touched_transactions)
    {%- endif %}
),

legs as (
    select * from swap_legs
    where leg_type = 'user'
),

transaction_legs as (
    select
        tx_id,
        count(*) as leg_count,
        sum(liquidity_fee_e8)::bigint as liquidity_fee_e8,
        sum(liquidity_fee_usd) as liquidity_fee_usd,
        sum(swap_volume_e8)::bigint as swap_volume_e8,
        sum(swap_volume_usd) as swap_volume_usd
    from swap_legs
    group by tx_id
),

swap_ends as (
    select
        tx_id,
        min(event_id) as first_event_id,
        min(block_height) as block_height,
        min(block_time) as block_time,
        max(block_height) as end_block_height,
        max(block_time) as end_block_time,
        (array_agg(chain order by event_id))[1] as chain,
        (array_agg(from_address order by event_id))[1] as from_address,
        (array_agg(from_asset order by event_id))[1] as from_asset,
        -- The output is what the RUNE-to-asset hop paid out; swaps with no such hop end in RUNE.
        coalesce(
            (array_agg(to_asset order by event_id desc) filter (where from_asset = 'THOR.RUNE'))[1],
            'THOR.RUNE'
        ) as to_asset,
        (array_agg(memo order by event_id))[1] as memo,
        (array_agg(tx_type order by event_id))[1] as tx_type,
        bool_or(is_streaming) as is_streaming,
        max(streaming_quantity) as streaming_quantity,
        max(streaming_count) as last_streaming_count,
        sum(liquidity_fee_e8)::bigint as user_liquidity_fee_e8
    from legs
    group by tx_id
),

-- Before affiliate fee events exist, the fee was skimmed from the input and sold in its own leg, so the
-- full input is the user legs plus that leg. Later fee legs sell the output asset and are left out.
-- (RUNE and synths deposited on THORChain paid the fee by transfer, not a leg; see native_input_fees.)
swap_amounts as (
    select
        swap_ends.tx_id,
        sum(legs.from_amount_e8) filter (where legs.from_asset = swap_ends.from_asset)::bigint as from_amount_e8,
        sum(legs.from_amount_usd) filter (where legs.from_asset = swap_ends.from_asset) as from_amount_usd,
        sum(legs.swap_volume_e8) filter (where legs.leg_type = 'user' and legs.from_asset = swap_ends.from_asset)::bigint as input_value_e8,
        sum(legs.to_amount_e8) filter (where legs.leg_type = 'user' and legs.to_asset = swap_ends.to_asset)::bigint as to_amount_e8,
        sum(legs.to_amount_usd) filter (where legs.leg_type = 'user' and legs.to_asset = swap_ends.to_asset) as to_amount_usd
    from swap_ends
    inner join swap_legs as legs
        on legs.tx_id = swap_ends.tx_id
    group by swap_ends.tx_id
),

affiliate_fees as (
    select * from {{ ref('core__affiliate_fees') }}
    {%- if is_incremental() %}
    where tx_id in (select tx_id from touched_transactions)
    {%- endif %}
),

-- Before affiliate fee events exist, a swap from RUNE or a synth deposited on THORChain paid its affiliate
-- fee from the deposit by transfer rather than in a leg, so the fee taken is added back to give the full
-- deposit. (Midgard's swap input leaves it out.) Trade-asset inputs had no fee taken.
native_fee_rows as (
    select
        fees.*,
        case when fees.asset like '%/%' then replace(fees.asset, '/', '.') end as pool
    from affiliate_fees as fees
    inner join swap_ends
        on swap_ends.tx_id = fees.tx_id
        and swap_ends.from_asset = fees.asset
    where fees.asset = 'THOR.RUNE' or fees.asset like '%/%'
),

native_fee_prices as {{ asset_prices_as_of('native_fee_rows') }},

native_input_fees as (
    select
        fees.tx_id,
        sum(fees.fee_amount_e8)::bigint as fee_amount_e8,
        sum(
            {{ units('fees.fee_amount_e8') }} * prices.rune_price_usd
            * case when fees.asset = 'THOR.RUNE' then 1 else asset_prices.asset_price end
        ) as fee_amount_usd
    from native_fee_rows as fees
    left join {{ ref('core__rune_price') }} as prices
        on prices.block_height = fees.block_height
    left join native_fee_prices as asset_prices
        on asset_prices.pool = fees.pool
        and asset_prices.block_height = fees.block_height
    group by fees.tx_id
),

fee_affiliates as (
    select
        tx_id,
        array_agg(affiliate order by first_event_id) as affiliates,
        sum(affiliate_fee_bps)::bigint as affiliate_fee_bps,
        sum(affiliate_fee_e8)::bigint as affiliate_fee_e8,
        sum(affiliate_fee_usd) as affiliate_fee_usd,
        bool_or(is_estimated) as is_affiliate_fee_estimated
    from (
        select
            tx_id,
            affiliate,
            min(event_id) as first_event_id,
            max(affiliate_fee_bps) as affiliate_fee_bps,
            sum(affiliate_fee_e8)::bigint as affiliate_fee_e8,
            sum(affiliate_fee_usd) as affiliate_fee_usd,
            bool_or(is_estimated) as is_estimated
        from affiliate_fees
        group by tx_id, affiliate
    ) as per_affiliate
    group by tx_id
),

-- THORNode reports a streaming swap's result once, when it finishes: sub-swaps carried out (failed ones
-- included), the amount deposited and the amount swapped; any remainder was refunded.
streaming_results as (
    select distinct on (tx_id)
        tx_id,
        streaming_count,
        deposit_amount_e8,
        in_amount_e8
    from (
        {%- if is_incremental() %}
        {{ events__streaming_swaps_sql(midgard_rows(
            'streaming_swap_details_events',
            'block_timestamp >= (select coalesce(min(timestamp), 0) from ' ~ source('midgard', 'block_log')
                ~ ' where height >= (select min(block_height) from swap_legs))'
        )) }}
        {%- else %}
        {{ events__streaming_swaps_sql(source('midgard', 'streaming_swap_details_events')) }}
        {%- endif %}
    ) as results
    where tx_id in (select tx_id from swap_ends)
    order by tx_id, event_id desc
),

-- Streaming swaps started before THORNode reported results (v1.117) have none; they are long finished.
first_streaming_result as (
    select coalesce(
        (
            select event_id
            from {{ source('midgard', 'streaming_swap_details_events') }}
            order by block_timestamp, event_id
            limit 1
        ),
        9223372036854775807
    ) as event_id
),

combined as (
    select
        swap_ends.*,
        coalesce(streaming_results.streaming_count, swap_ends.last_streaming_count) as streaming_count,
        case
            when not swap_ends.is_streaming then 'completed'
            when streaming_results.tx_id is not null then
                case
                    when streaming_results.deposit_amount_e8 > streaming_results.in_amount_e8 then 'partly_refunded'
                    else 'completed'
                end
            when swap_ends.first_event_id < (select event_id from first_streaming_result) then
                case
                    when swap_ends.last_streaming_count >= swap_ends.streaming_quantity then 'completed'
                    else 'partly_refunded'
                end
            else 'in_progress'
        end as status,
        transaction_legs.leg_count,
        transaction_legs.liquidity_fee_e8,
        transaction_legs.liquidity_fee_usd,
        transaction_legs.swap_volume_e8,
        transaction_legs.swap_volume_usd,
        swap_amounts.from_amount_e8 + coalesce(native_input_fees.fee_amount_e8, 0) as from_amount_e8,
        swap_amounts.from_amount_usd + coalesce(native_input_fees.fee_amount_usd, 0) as from_amount_usd,
        swap_amounts.input_value_e8,
        swap_amounts.to_amount_e8,
        swap_amounts.to_amount_usd,
        coalesce(
            fee_affiliates.affiliates,
            string_to_array({{ swap_memo_field('swap_ends.memo', 5) }}, '/')
        ) as affiliates,
        fee_affiliates.affiliate_fee_bps,
        fee_affiliates.affiliate_fee_e8,
        fee_affiliates.affiliate_fee_usd,
        fee_affiliates.is_affiliate_fee_estimated
    from swap_ends
    inner join transaction_legs
        on transaction_legs.tx_id = swap_ends.tx_id
    inner join swap_amounts
        on swap_amounts.tx_id = swap_ends.tx_id
    left join native_input_fees
        on native_input_fees.tx_id = swap_ends.tx_id
    left join fee_affiliates
        on fee_affiliates.tx_id = swap_ends.tx_id
    left join streaming_results
        on streaming_results.tx_id = swap_ends.tx_id
)

select
    tx_id,
    block_height,
    block_time,
    (block_time at time zone 'UTC')::date as day,
    end_block_height,
    end_block_time,
    chain,
    from_address,
    {{ swap_memo_field('memo', 3) }} as to_address,
    from_asset,
    {{ units('from_amount_e8') }} as from_amount,
    from_amount_e8,
    from_amount_usd,
    to_asset,
    {{ units('to_amount_e8') }} as to_amount,
    to_amount_e8,
    to_amount_usd,
    from_amount_usd as user_volume_usd,
    {{ units('swap_volume_e8') }} as swap_volume,
    swap_volume_e8,
    swap_volume_usd,
    {{ units('liquidity_fee_e8') }} as liquidity_fee,
    liquidity_fee_e8,
    liquidity_fee_usd,
    round(user_liquidity_fee_e8 * 10000.0 / nullif(input_value_e8, 0), 2) as liquidity_fee_bps,
    affiliates[1] as affiliate,
    affiliates,
    affiliate_fee_bps,
    {{ units('affiliate_fee_e8') }} as affiliate_fee,
    affiliate_fee_e8,
    affiliate_fee_usd,
    is_affiliate_fee_estimated,
    leg_count,
    is_streaming,
    streaming_quantity,
    streaming_count,
    status,
    tx_type,
    memo
from combined
