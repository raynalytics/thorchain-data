{{ config(
    materialized='incremental',
    unique_key='block_height',
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['block_height'], 'unique': true}, {'columns': ['day']}]
) }}

{%- if is_incremental() %}
{%- set last_block = high_water_block() %}
{%- endif %}

-- Midgard records 0 when no price anchor pool was usable in a block. Those blocks take the last
-- recorded price instead, and is_price_recorded is false. Incremental runs carry the price on from
-- the last block already in the table.
with prices as (
    select
        blocks.height as block_height,
        blocks.timestamp,
        nullif(prices.rune_price_e8, 0)::numeric as recorded_price_usd,
        false as is_carried_in
    from {{ source('midgard', 'rune_price') }} as prices
    inner join {{ source('midgard', 'block_log') }} as blocks
        on blocks.timestamp = prices.block_timestamp
    {%- if is_incremental() %}
    where prices.block_timestamp > {{ block_timestamp_ns(last_block) }}
        and blocks.height > {{ last_block }}

    union all

    select block_height, null, rune_price_usd, true
    from {{ this }}
    where block_height = {{ last_block }}
    {%- endif %}
),

grouped as (
    select
        *,
        count(recorded_price_usd) over (order by block_height) as price_group
    from prices
),

carried as (
    select
        *,
        first_value(recorded_price_usd) over (partition by price_group order by block_height) as rune_price_usd
    from grouped
)

select
    block_height,
    {{ block_time('timestamp') }} as block_time,
    {{ block_day('timestamp') }} as day,
    rune_price_usd,
    recorded_price_usd is not null as is_price_recorded
from carried
where not is_carried_in
