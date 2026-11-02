select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    asset as pool,
    {{ units('case when rune_add then rune_amt else -rune_amt end') }} as rune_change,
    case when rune_add then rune_amt else -rune_amt end as rune_change_e8,
    {{ units('case when asset_add then asset_amt else -asset_amt end') }} as asset_change,
    case when asset_add then asset_amt else -asset_amt end as asset_change_e8,
    reason
from {{ source('midgard', 'pool_balance_change_events') }}
