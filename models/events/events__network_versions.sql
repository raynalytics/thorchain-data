select
    event_id,
    {{ block_height('event_id') }} as block_height,
    {{ block_time('block_timestamp') }} as block_time,
    version
from {{ source('midgard', 'network_version_events') }}
