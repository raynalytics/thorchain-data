{{ config(
    materialized='incremental',
    unique_key='event_id',
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['event_id'], 'unique': true}, {'columns': ['block_height']}, {'columns': ['day']}]
) }}

{%- if is_incremental() %}
{%- set since_ns = block_timestamp_ns(high_water_block()) %}
{%- set adds = events__liquidity_adds_sql(midgard_rows('stake_events', 'block_timestamp > ' ~ since_ns)) %}
{%- set withdrawals = events__liquidity_withdrawals_sql(midgard_rows('withdraw_events', 'block_timestamp > ' ~ since_ns)) %}
{%- else %}
{%- set adds = events__liquidity_adds_sql(source('midgard', 'stake_events')) %}
{%- set withdrawals = events__liquidity_withdrawals_sql(source('midgard', 'withdraw_events')) %}
{%- endif %}

with actions as (
    select
        event_id,
        block_height,
        block_time,
        'add' as action,
        pool,
        coalesce(asset_tx_id, rune_tx_id) as tx_id,
        rune_address,
        asset_address,
        rune_amount_e8,
        asset_amount_e8,
        liquidity_units_added as liquidity_units_change,
        null::bigint as basis_points,
        null::double precision as asymmetry,
        0::bigint as impermanent_loss_protection_e8,
        memo
    from ({{ adds }}) as adds

    union all

    select
        event_id,
        block_height,
        block_time,
        'withdraw' as action,
        pool,
        tx_id,
        case when from_address like 'thor1%' then from_address end as rune_address,
        case when from_address not like 'thor1%' then from_address end as asset_address,
        rune_amount_e8,
        asset_amount_e8,
        -liquidity_units_removed as liquidity_units_change,
        basis_points,
        asymmetry,
        impermanent_loss_protection_e8,
        memo
    from ({{ withdrawals }}) as withdrawals
),

asset_prices as {{ asset_prices_as_of('actions') }},

priced as (
    select
        actions.*,
        prices.rune_price_usd,
        asset_prices.asset_price * prices.rune_price_usd as asset_price_usd
    from actions
    left join {{ ref('core__rune_price') }} as prices
        on prices.block_height = actions.block_height
    left join asset_prices
        on asset_prices.pool = actions.pool
        and asset_prices.block_height = actions.block_height
)

select
    event_id,
    block_height,
    block_time,
    (block_time at time zone 'UTC')::date as day,
    action,
    pool,
    tx_id,
    rune_address,
    asset_address,
    {{ units('rune_amount_e8') }} as rune_amount,
    rune_amount_e8,
    {{ units('rune_amount_e8') }} * rune_price_usd as rune_amount_usd,
    {{ units('asset_amount_e8') }} as asset_amount,
    asset_amount_e8,
    {{ units('asset_amount_e8') }} * asset_price_usd as asset_amount_usd,
    {{ units('rune_amount_e8') }} * rune_price_usd
        + {{ units('asset_amount_e8') }} * asset_price_usd as total_value_usd,
    liquidity_units_change,
    basis_points,
    asymmetry,
    {{ units('impermanent_loss_protection_e8') }} as impermanent_loss_protection,
    impermanent_loss_protection_e8,
    {{ units('impermanent_loss_protection_e8') }} * rune_price_usd as impermanent_loss_protection_usd,
    memo
from priced
