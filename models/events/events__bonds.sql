with bond_events as (
    select
        *,
        case
            when bond_type in ('bond_paid', 'bond_reward') then e8
            when bond_type in ('bond_returned', 'bond_cost') then -e8
            else 0
        end as bond_change_e8
    from {{ source('midgard', 'bond_events') }}
)

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
    bond_type,
    {{ units('e8') }} as bond_amount,
    e8 as bond_amount_e8,
    {{ units('bond_change_e8') }} as bond_change,
    bond_change_e8,
    bond_addr as bond_address,
    node_addr as node_address,
    signer_addr as signer_address,
    _tx_type as tx_type,
    memo
from bond_events
