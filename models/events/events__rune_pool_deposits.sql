select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    rune_addr as rune_address,
    {{ units('amount_e8') }} as amount,
    amount_e8,
    units as rune_pool_units
from {{ source('midgard', 'rune_pool_deposit_events') }}
