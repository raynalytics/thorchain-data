{#- Asset price in RUNE of each distinct (pool, block_height) in `keys` (a CTE or relation with those
    columns), from the pool's latest depth record at or before that block. The keys are merged with
    the pools' depth records in one sorted pass (an as-of join): for each pool, its last record at or
    before its first key, then its records up to its last key. -#}
{% macro asset_prices_as_of(keys) -%}
    (
        with price_keys as (
            select distinct pool, block_height
            from {{ keys }}
            where pool is not null
        ),

        key_ranges as (
            select
                pool,
                min(block_height) as first_height,
                max(block_height) as last_height
            from price_keys
            group by pool
        ),

        points as (
            select key_ranges.pool, seed.block_height, seed.asset_price, 0 as is_key
            from key_ranges
            cross join lateral (
                select depths.block_height, depths.asset_price
                from {{ ref('core__pool_depths') }} as depths
                where depths.pool = key_ranges.pool
                    and depths.block_height <= key_ranges.first_height
                order by depths.block_height desc
                limit 1
            ) as seed

            union all

            select depths.pool, depths.block_height, depths.asset_price, 0
            from {{ ref('core__pool_depths') }} as depths
            inner join key_ranges
                on key_ranges.pool = depths.pool
                and depths.block_height > key_ranges.first_height
                and depths.block_height <= key_ranges.last_height

            union all

            select pool, block_height, null, 1
            from price_keys
        ),

        grouped as (
            select
                *,
                count(*) filter (where is_key = 0) over (
                    partition by pool order by block_height, is_key rows between unbounded preceding and current row
                ) as depth_group
            from points
        ),

        carried as (
            select
                pool,
                block_height,
                is_key,
                first_value(asset_price) over (
                    partition by pool, depth_group order by block_height, is_key
                ) as asset_price
            from grouped
        )

        select pool, block_height, asset_price
        from carried
        where is_key = 1
    )
{%- endmacro %}

{#- One row per UTC day from the first (or `start_day`) to the last indexed block, with the last RUNE
    price of that day, carried forward over days with no block. From `start_day`, the carry starts
    from the last price before that day. -#}
{% macro end_of_day_rune_price(start_day=none) -%}
    select day, rune_price_usd
    from (
    select
        day,
        first_value(rune_price_usd) over (partition by price_group order by day) as rune_price_usd
    from (
        select
            days.day,
            prices.rune_price_usd,
            count(prices.rune_price_usd) over (order by days.day) as price_group
        from (
            {%- if start_day is none %}
            select generate_series(min(day), max(day), interval '1 day')::date as day
            from {{ ref('core__blocks') }}
            {%- else %}
            select (date '{{ start_day }}' - 1) as day
            union all
            select generate_series(
                date '{{ start_day }}',
                (select day from {{ ref('core__blocks') }} order by block_height desc limit 1),
                interval '1 day'
            )::date
            {%- endif %}
        ) as days
        left join (
            select
                day,
                (array_agg(rune_price_usd order by block_height desc)
                    filter (where rune_price_usd is not null))[1] as rune_price_usd
            from {{ ref('core__rune_price') }}
            {%- if start_day is not none %}
            where block_height >= {{ first_block_of("date '" ~ start_day ~ "'") }}
            {%- endif %}
            group by day
            {%- if start_day is not none %}

            union all

            -- Last price before the start day, carried into it.
            select (date '{{ start_day }}' - 1), (
                select rune_price_usd
                from {{ ref('core__rune_price') }}
                where block_height < {{ first_block_of("date '" ~ start_day ~ "'") }}
                    and rune_price_usd is not null
                order by block_height desc
                limit 1
            )
            {%- endif %}
        ) as prices
            on prices.day = days.day
    ) as daily_prices
    ) as carried_prices
    {%- if start_day is not none %}
    where day >= date '{{ start_day }}'
    {%- endif %}
{%- endmacro %}
