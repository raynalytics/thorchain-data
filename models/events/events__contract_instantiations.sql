select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    contract_address,
    admin_address,
    code_id,
    sender as sender_address,
    label,
    msg,
    funds
from {{ source('midgard', 'instantiate_events') }}
