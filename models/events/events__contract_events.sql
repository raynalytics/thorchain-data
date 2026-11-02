select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    contract_address,
    contract_type,
    sender as sender_address,
    attributes,
    msg,
    funds
from {{ source('midgard', 'wasm_contracts_events') }}
