select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    {{ block_day('block_timestamp') }} as day,
    node_addr as node_address,
    former as previous_status,
    current as status,
    case
        when current = 'Active' and former is distinct from 'Active' then 1
        when former = 'Active' and current is distinct from 'Active' then -1
        else 0
    end as active_node_change
from {{ source('midgard', 'update_node_account_status_events') }}
