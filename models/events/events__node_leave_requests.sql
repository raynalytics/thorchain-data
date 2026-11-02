select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx as tx_id,
    from_addr as from_address,
    node_addr as node_address
from {{ source('midgard', 'validator_request_leave_events') }}
