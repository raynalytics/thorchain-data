select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    from_addr as from_address,
    asset,
    {{ units('amount_e8') }} as amount,
    amount_e8,
    code,
    reason,
    memo
from {{ source('midgard', 'failed_deposit_messages') }}
