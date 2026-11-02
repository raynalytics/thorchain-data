select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx as tx_id,
    asset,
    {{ units('asset_e8') }} as amount,
    asset_e8 as amount_e8,
    vault_key as vault_pubkey
from {{ source('midgard', 'asgard_fund_yggdrasil_events') }}
