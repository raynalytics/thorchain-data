select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    asset,
    {{ units('amount_e8') }} as amount,
    amount_e8,
    asset_address,
    rune_address
from {{ source('midgard', 'secure_asset_withdraw_events') }}
