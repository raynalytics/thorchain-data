select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    from_addr as from_address,
    to_addr as to_address,
    from_asset,
    {{ units('from_e8') }} as from_amount,
    from_e8 as from_amount_e8,
    to_asset,
    {{ units('to_e8') }} as to_amount,
    to_e8 as to_amount_e8,
    memo
from {{ source('midgard', 'limit_swap_events') }}
