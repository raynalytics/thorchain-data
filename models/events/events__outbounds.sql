select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx as tx_id,
    in_tx as in_tx_id,
    chain,
    from_addr as from_address,
    to_addr as to_address,
    asset,
    {{ units('asset_e8') }} as amount,
    asset_e8 as amount_e8,
    internal as is_internal,
    _tx_type as tx_type,
    memo
from {{ source('midgard', 'outbound_events') }}
