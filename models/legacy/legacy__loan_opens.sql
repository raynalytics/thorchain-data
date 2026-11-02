select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    owner as owner_address,
    collateral_asset,
    {{ units('collateral_deposited') }} as collateral_deposited,
    collateral_deposited as collateral_deposited_e8,
    target_asset,
    {{ units('debt_issued') }} as debt_issued,
    debt_issued as debt_issued_e8,
    collateralization_ratio as collateralization_ratio_bps
from {{ source('midgard', 'loan_open_events') }}
