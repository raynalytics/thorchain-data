select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx as tx_id,
    chain,
    from_addr as from_address,
    to_addr as to_address,
    asset,
    {{ units('asset_e8') }} as amount,
    asset_e8 as amount_e8,
    addr as contributor_address,
    {{ units('e8') }} as rune_amount,
    e8 as rune_amount_e8,
    _tx_type as tx_type,
    memo
from {{ source('midgard', 'reserve_events') }}
