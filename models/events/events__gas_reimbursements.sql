select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    asset as pool,
    {{ units('asset_e8') }} as asset_amount,
    asset_e8 as asset_amount_e8,
    {{ units('rune_e8') }} as rune_amount,
    rune_e8 as rune_amount_e8,
    tx_count
from {{ source('midgard', 'gas_events') }}
