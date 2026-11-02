select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    node_address,
    slash_points,
    reason
from {{ source('midgard', 'slash_points_events') }}
