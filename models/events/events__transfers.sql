select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    from_addr as from_address,
    to_addr as to_address,
    asset,
    {{ units('amount_e8') }} as amount,
    amount_e8
from {{ source('midgard', 'transfer_events') }}
