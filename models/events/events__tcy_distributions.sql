select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    rune_address,
    {{ units('rune_amt') }} as amount,
    rune_amt as amount_e8
from {{ source('midgard', 'tcy_distribution_events') }}
