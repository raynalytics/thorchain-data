select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    add_asgard_addr as vault_pubkey
from {{ source('midgard', 'active_vault_events') }}
