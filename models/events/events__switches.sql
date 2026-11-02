select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx as tx_id,
    from_addr as from_address,
    to_addr as to_address,
    burn_asset,
    {{ units('burn_e8') }} as burn_amount,
    burn_e8 as burn_amount_e8,
    mint_asset,
    {{ units('mint_e8') }} as mint_amount,
    mint_e8 as mint_amount_e8
from {{ source('midgard', 'switch_events') }}
