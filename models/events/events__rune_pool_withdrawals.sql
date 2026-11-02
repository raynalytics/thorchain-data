select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    rune_addr as rune_address,
    {{ units('amount_e8') }} as amount,
    amount_e8,
    units as rune_pool_units,
    basis_points,
    affiliate_addr as affiliate_address,
    affiliate_basis_pts as affiliate_fee_bps,
    {{ units('affiliate_amount_e8') }} as affiliate_fee,
    affiliate_amount_e8 as affiliate_fee_e8
from {{ source('midgard', 'rune_pool_withdraw_events') }}
