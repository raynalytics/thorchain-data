select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    pub_key as vault_pubkey,
    members as member_pubkeys,
    height as keygen_block_height
from {{ source('midgard', 'tss_keygen_success_events') }}
