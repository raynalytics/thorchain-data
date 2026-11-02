select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    address as node_address,
    key,
    value
from {{ source('midgard', 'set_node_mimir_events') }}
