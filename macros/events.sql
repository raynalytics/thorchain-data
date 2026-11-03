{#- SQL of the event views that incremental models also read. Each takes the Midgard table (or a
    filtered subquery of it, see midgard_rows) so the view and the models share one definition. -#}

{% macro events__swaps_sql(midgard_table) -%}
select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx as tx_id,
    chain,
    from_addr as from_address,
    to_addr as to_address,
    pool,
    from_asset,
    {{ units('from_e8') }} as from_amount,
    from_e8 as from_amount_e8,
    to_asset,
    {{ units('to_e8') }} as to_amount,
    to_e8 as to_amount_e8,
    {{ units('to_e8_min') }} as min_to_amount,
    to_e8_min as min_to_amount_e8,
    swap_slip_bp as swap_slip_bps,
    {{ units('liq_fee_in_rune_e8') }} as liquidity_fee,
    liq_fee_in_rune_e8 as liquidity_fee_e8,
    {{ units('liq_fee_e8') }} as liquidity_fee_in_to_asset,
    liq_fee_e8 as liquidity_fee_in_to_asset_e8,
    case _direction
        when 0 then 'rune_to_asset'
        when 1 then 'asset_to_rune'
        when 2 then 'rune_to_synth'
        when 3 then 'synth_to_rune'
        when 4 then 'rune_to_derived'
        when 5 then 'derived_to_rune'
        when 6 then 'rune_to_trade'
        when 7 then 'trade_to_rune'
        when 8 then 'rune_to_secured'
        when 9 then 'secured_to_rune'
    end as direction,
    _streaming as is_streaming,
    streaming_count,
    streaming_quantity,
    _tx_type as tx_type,
    memo
from {{ midgard_table }}
{%- endmacro %}

{% macro events__transfers_sql(midgard_table) -%}
select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    from_addr as from_address,
    to_addr as to_address,
    asset,
    {{ units('amount_e8') }} as amount,
    amount_e8
from {{ midgard_table }}
{%- endmacro %}

{% macro events__streaming_swaps_sql(midgard_table) -%}
select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    interval as interval_blocks,
    quantity as streaming_quantity,
    count as streaming_count,
    last_height as last_block_height,
    deposit_asset,
    {{ units('deposit_e8') }} as deposit_amount,
    deposit_e8 as deposit_amount_e8,
    in_asset,
    {{ units('in_e8') }} as in_amount,
    in_e8 as in_amount_e8,
    out_asset,
    {{ units('out_e8') }} as out_amount,
    out_e8 as out_amount_e8,
    failed_swaps,
    failed_swap_reasons
from {{ midgard_table }}
{%- endmacro %}

{% macro events__liquidity_adds_sql(midgard_table) -%}
select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    pool,
    asset_tx as asset_tx_id,
    asset_chain,
    asset_addr as asset_address,
    {{ units('asset_e8') }} as asset_amount,
    asset_e8 as asset_amount_e8,
    rune_tx as rune_tx_id,
    rune_addr as rune_address,
    {{ units('rune_e8') }} as rune_amount,
    rune_e8 as rune_amount_e8,
    stake_units as liquidity_units_added,
    {{ units('_asset_in_rune_e8') }} as asset_value_in_rune,
    _asset_in_rune_e8 as asset_value_in_rune_e8,
    memo
from {{ midgard_table }}
{%- endmacro %}

{% macro events__liquidity_withdrawals_sql(midgard_table) -%}
select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx as tx_id,
    chain,
    from_addr as from_address,
    to_addr as to_address,
    pool,
    asset,
    {{ units('asset_e8') }} as amount,
    asset_e8 as amount_e8,
    {{ units('emit_asset_e8') }} as asset_amount,
    emit_asset_e8 as asset_amount_e8,
    {{ units('emit_rune_e8') }} as rune_amount,
    emit_rune_e8 as rune_amount_e8,
    stake_units as liquidity_units_removed,
    basis_points,
    asymmetry,
    {{ units('imp_loss_protection_e8') }} as impermanent_loss_protection,
    imp_loss_protection_e8 as impermanent_loss_protection_e8,
    {{ units('_emit_asset_in_rune_e8') }} as asset_value_in_rune,
    _emit_asset_in_rune_e8 as asset_value_in_rune_e8,
    _tx_type as tx_type,
    memo
from {{ midgard_table }}
{%- endmacro %}

{% macro events__pool_rewards_sql(midgard_table) -%}
select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    pool,
    {{ units('rune_e8') }} as pool_rewards,
    rune_e8 as pool_rewards_e8,
    {{ units('saver_e8') }} as saver_rewards,
    saver_e8 as saver_rewards_e8
from {{ midgard_table }}
{%- endmacro %}

{% macro events__rewards_sql(midgard_table) -%}
select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    {{ units('bond_e8') }} as bond_rewards,
    bond_e8 as bond_rewards_e8
from {{ midgard_table }}
{%- endmacro %}

{% macro events__bonds_sql(midgard_table) -%}
with bond_events as (
    select
        *,
        case
            when bond_type in ('bond_paid', 'bond_reward') then e8
            when bond_type in ('bond_returned', 'bond_cost') then -e8
            else 0
        end as bond_change_e8
    from {{ midgard_table }}
)

select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx as tx_id,
    chain,
    from_addr as from_address,
    to_addr as to_address,
    asset,
    {{ units('asset_e8') }} as amount,
    asset_e8 as amount_e8,
    bond_type,
    {{ units('e8') }} as bond_amount,
    e8 as bond_amount_e8,
    {{ units('bond_change_e8') }} as bond_change,
    bond_change_e8,
    bond_addr as bond_address,
    node_addr as node_address,
    signer_addr as signer_address,
    _tx_type as tx_type,
    memo
from bond_events
{%- endmacro %}
