select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    asset,
    {{ units('asset_e8') }} as amount,
    asset_e8 as amount_e8,
    {{ units('supply') }} as supply,
    supply as supply_e8,
    reason
from {{ source('midgard', 'mint_burn_events') }}
