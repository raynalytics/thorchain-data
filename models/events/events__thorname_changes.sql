select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    name as thorname,
    chain,
    address,
    owner as owner_address,
    sender as sender_address,
    expire as expiry_block_height,
    {{ units('registration_fee_e8') }} as registration_fee,
    registration_fee_e8,
    {{ units('fund_amount_e8') }} as fund_amount,
    fund_amount_e8,
    memo
from {{ source('midgard', 'thorname_change_events') }}
