select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    node_address,
    old_bond_address,
    new_bond_address,
    to_addr as to_address,
    {{ units('amount') }} as amount,
    amount as amount_e8,
    memo
from {{ source('midgard', 'rebond_events') }}
