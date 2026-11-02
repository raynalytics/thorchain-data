select
    height as block_height,
    {{ block_time('timestamp') }} as block_time,
    {{ block_day('timestamp') }} as day,
    upper(encode(hash, 'hex')) as block_hash
from {{ source('midgard', 'block_log') }}
