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
from {{ source('midgard', 'stake_events') }}
