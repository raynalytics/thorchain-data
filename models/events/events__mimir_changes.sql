select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    key,
    value
from {{ source('midgard', 'set_mimir_events') }}
