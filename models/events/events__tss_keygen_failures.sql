select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    fail_reason,
    is_unicast,
    blame_nodes as blamed_node_addresses,
    round,
    height as keygen_block_height
from {{ source('midgard', 'tss_keygen_failure_events') }}
