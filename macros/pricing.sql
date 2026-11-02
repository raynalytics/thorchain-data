{#- Price of a pool's asset in RUNE from the pool's latest depths at or before a block. -#}
{% macro asset_price_at(pool_column, block_height_column) -%}
    (
        select depths.asset_price
        from {{ ref('core__pool_depths') }} as depths
        where depths.pool = {{ pool_column }}
            and depths.block_height <= {{ block_height_column }}
        order by depths.block_height desc
        limit 1
    )
{%- endmacro %}

{#- One row per UTC day from the first to the last indexed block, with the last recorded RUNE price
    of that day, carried forward over days with no usable price. -#}
{% macro end_of_day_rune_price() -%}
    select
        day,
        first_value(rune_price_usd) over (partition by price_group order by day) as rune_price_usd
    from (
        select
            days.day,
            prices.rune_price_usd,
            count(prices.rune_price_usd) over (order by days.day) as price_group
        from (
            select generate_series(min(day), max(day), interval '1 day')::date as day
            from {{ ref('core__blocks') }}
        ) as days
        left join (
            select
                day,
                (array_agg(rune_price_usd order by block_height desc)
                    filter (where rune_price_usd is not null))[1] as rune_price_usd
            from {{ ref('core__rune_price') }}
            group by day
        ) as prices
            on prices.day = days.day
    ) as daily_prices
{%- endmacro %}
