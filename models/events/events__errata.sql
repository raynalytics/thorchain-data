select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    in_tx as tx_id,
    asset as pool,
    {{ units('asset_e8') }} as asset_amount,
    asset_e8 as asset_amount_e8,
    {{ units('rune_e8') }} as rune_amount,
    rune_e8 as rune_amount_e8
from {{ source('midgard', 'errata_events') }}
