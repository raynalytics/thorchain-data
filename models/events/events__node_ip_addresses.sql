select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    node_addr as node_address,
    ip_addr as ip_address
from {{ source('midgard', 'set_ip_address_events') }}
