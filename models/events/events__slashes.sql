select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    pool,
    asset,
    {{ units('asset_e8') }} as amount,
    asset_e8 as amount_e8
from {{ source('midgard', 'slash_events') }}
