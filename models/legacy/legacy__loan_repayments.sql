select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    tx_id,
    owner as owner_address,
    collateral_asset,
    {{ units('collateral_withdrawn') }} as collateral_withdrawn,
    collateral_withdrawn as collateral_withdrawn_e8,
    {{ units('debt_repaid') }} as debt_repaid,
    debt_repaid as debt_repaid_e8
from {{ source('midgard', 'loan_repayment_events') }}
