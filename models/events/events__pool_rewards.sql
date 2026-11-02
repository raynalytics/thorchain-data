select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    pool,
    {{ units('rune_e8') }} as pool_rewards,
    rune_e8 as pool_rewards_e8,
    {{ units('saver_e8') }} as saver_rewards,
    saver_e8 as saver_rewards_e8
from {{ source('midgard', 'rewards_event_entries') }}
