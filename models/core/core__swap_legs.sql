{{ config(indexes=[{'columns': ['tx_id']}, {'columns': ['block_height']}]) }}

with legs as (
    select
        swaps.*,
        prices.rune_price_usd,
        {{ asset_price_at('swaps.pool', 'swaps.block_height') }} as asset_price
    from {{ ref('events__swaps') }} as swaps
    left join {{ ref('core__rune_price') }} as prices
        on prices.block_height = swaps.block_height
),

valued as (
    select
        *,
        asset_price * rune_price_usd as asset_price_usd,
        -- Midgard's volume measure: the RUNE side of the leg, fee included.
        case
            when direction like 'rune_to_%' then from_amount_e8
            when direction like '%_to_rune' then to_amount_e8 + liquidity_fee_e8
            else 0
        end as swap_volume_e8
    from legs
)

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
    memo
from valued
