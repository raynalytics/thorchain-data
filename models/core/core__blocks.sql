{{ config(
    materialized='incremental',
    unique_key='block_height',
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['block_height'], 'unique': true}, {'columns': ['day']}]
) }}

select
    height as block_height,
    {{ block_time('timestamp') }} as block_time,
    {{ block_day('timestamp') }} as day,
    upper(encode(hash, 'hex')) as block_hash
from {{ source('midgard', 'block_log') }}
{%- if is_incremental() %}
where height > {{ high_water_block() }}
{%- endif %}
