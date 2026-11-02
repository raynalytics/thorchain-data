select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx as tx_id,
    asset,
    {{ units('asset_e8') }} as amount,
    asset_e8 as amount_e8,
    {{ units('pool_deduct') }} as pool_deduct,
    pool_deduct as pool_deduct_e8
from {{ source('midgard', 'fee_events') }}
