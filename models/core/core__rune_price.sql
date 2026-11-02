{{ config(indexes=[{'columns': ['block_height'], 'unique': true}]) }}

-- Midgard records 0 when no price anchor pool was usable in a block. Those blocks take the last
-- recorded price instead, and is_price_recorded is false.
with prices as (
    select
        blocks.height as block_height,
        blocks.timestamp,
        nullif(prices.rune_price_e8, 0)::numeric as recorded_price_usd
    from {{ source('midgard', 'rune_price') }} as prices
    inner join {{ source('midgard', 'block_log') }} as blocks
        on blocks.timestamp = prices.block_timestamp
),

grouped as (
    select
        *,
        count(recorded_price_usd) over (order by block_height) as price_group
    from prices
)

select
    block_height,
    {{ block_time('timestamp') }} as block_time,
    {{ block_day('timestamp') }} as day,
    first_value(recorded_price_usd) over (partition by price_group order by block_height) as rune_price_usd,
    recorded_price_usd is not null as is_price_recorded
from grouped
