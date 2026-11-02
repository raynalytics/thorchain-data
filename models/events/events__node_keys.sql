select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    node_addr as node_address,
    secp256k1 as secp256k1_pubkey,
    ed25519 as ed25519_pubkey,
    validator_consensus as validator_consensus_pubkey
from {{ source('midgard', 'set_node_keys_events') }}
