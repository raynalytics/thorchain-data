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
    asset_2nd as second_asset,
    {{ units('asset_2nd_e8') }} as second_amount,
    asset_2nd_e8 as second_amount_e8,
    code,
    reason,
    _tx_type as tx_type,
    memo
from {{ source('midgard', 'refund_events') }}
