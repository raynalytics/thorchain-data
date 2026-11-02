select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    from_addr as from_address,
    action
from {{ source('midgard', 'message_events') }}
