select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    rune_address,
    l1_address,
    asset,
    {{ units('tcy_amt') }} as amount,
    tcy_amt as amount_e8,
    memo
from {{ source('midgard', 'tcy_claim_events') }}
