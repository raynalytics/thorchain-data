select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    rune_address,
    {{ units('amount') }} as amount,
    amount as amount_e8,
    memo
from {{ source('midgard', 'tcy_unstake_events') }}
