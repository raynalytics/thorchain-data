select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    {{ units('bond_e8') }} as bond_rewards,
    bond_e8 as bond_rewards_e8
from {{ source('midgard', 'rewards_events') }}
