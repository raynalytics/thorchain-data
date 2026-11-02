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
from {{ source('midgard', 'swap_events') }}
