{{ config(
    materialized='incremental',
    unique_key='day',
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['day'], 'unique': true}]
) }}

{%- if is_incremental() %}
{%- set start_day = daily_start_day() %}
{%- set since_block = first_block_of("date '" ~ start_day ~ "'") %}
{%- endif %}

-- An incremental run recomputes the days from daily_start_day() on; bonded RUNE and active nodes
-- continue from the stored day before.
with rune_prices as (
    {%- if is_incremental() %}
    {{ end_of_day_rune_price(start_day) }}
    {%- else %}
    {{ end_of_day_rune_price() }}
    {%- endif %}
),

swaps as (
    select
        day,
        count(*) as swap_count,
        count(distinct from_address) as unique_swappers,
        sum(user_volume_usd) as user_volume_usd
    from {{ ref('core__swaps') }}
    {%- if is_incremental() %}
    where day >= date '{{ start_day }}'
    {%- endif %}
    group by day
),

swap_legs as (
    select
        day,
        sum(swap_volume_e8)::bigint as swap_volume_e8,
        sum(swap_volume_usd) as swap_volume_usd
    from {{ ref('core__swap_legs') }}
    {%- if is_incremental() %}
    where block_height >= {{ since_block }}
    {%- endif %}
    group by day
),

earnings as (
    select
        day,
        sum(liquidity_fee_e8)::bigint as liquidity_fee_e8,
        sum(liquidity_fee_usd) as liquidity_fee_usd,
        sum(pool_rewards_e8)::bigint as pool_rewards_e8,
        sum(pool_rewards_usd) as pool_rewards_usd,
        sum(bond_rewards_e8)::bigint as bond_rewards_e8,
        sum(bond_rewards_usd) as bond_rewards_usd,
        sum(block_rewards_e8)::bigint as block_rewards_e8,
        sum(block_rewards_usd) as block_rewards_usd,
        sum(liquidity_earnings_e8)::bigint as liquidity_earnings_e8,
        sum(liquidity_earnings_usd) as liquidity_earnings_usd,
        sum(earnings_e8)::bigint as earnings_e8,
        sum(earnings_usd) as earnings_usd
    from {{ ref('core__earnings') }}
    {%- if is_incremental() %}
    where block_height >= {{ since_block }}
    {%- endif %}
    group by day
),

pooled as (
    select
        day,
        sum(total_value_pooled_e8)::bigint as total_value_pooled_e8
    from {{ ref('daily__pools') }}
    {%- if is_incremental() %}
    where day >= date '{{ start_day }}'
    {%- endif %}
    group by day
),

bond_changes as (
    select
        (block_time at time zone 'UTC')::date as day,
        sum(bond_change_e8) as bond_change_e8
    {%- if is_incremental() %}
    from ({{ events__bonds_sql(midgard_rows(
        'bond_events', 'block_timestamp >= ' ~ day_start_ns("date '" ~ start_day ~ "'")
    )) }}) as bonds
    {%- else %}
    from {{ ref('events__bonds') }}
    {%- endif %}
    group by 1
),

node_changes as (
    select
        day,
        sum(active_node_change) as active_node_change
    from {{ ref('core__node_status_changes') }}
    {%- if is_incremental() %}
    where block_height >= {{ since_block }}
    {%- endif %}
    group by day
),

-- Bonded RUNE and active nodes are running totals of their changes, as Midgard computes them.
running as (
    select
        rune_prices.day,
        rune_prices.rune_price_usd,
        coalesce(pooled.total_value_pooled_e8, 0) as total_value_pooled_e8,
        {%- if is_incremental() %}
        previous.total_value_bonded_e8
            + sum(coalesce(bond_changes.bond_change_e8, 0)) over (order by rune_prices.day)::bigint as total_value_bonded_e8,
        previous.active_nodes
            + sum(coalesce(node_changes.active_node_change, 0)) over (order by rune_prices.day)::bigint as active_nodes
        {%- else %}
        sum(coalesce(bond_changes.bond_change_e8, 0)) over (order by rune_prices.day)::bigint as total_value_bonded_e8,
        sum(coalesce(node_changes.active_node_change, 0)) over (order by rune_prices.day)::bigint as active_nodes
        {%- endif %}
    from rune_prices
    {%- if is_incremental() %}
    cross join (
        select
            coalesce(max(total_value_bonded_e8), 0) as total_value_bonded_e8,
            coalesce(max(active_nodes), 0) as active_nodes
        from {{ this }}
        where day = date '{{ start_day }}' - 1
    ) as previous
    {%- endif %}
    left join pooled
        on pooled.day = rune_prices.day
    left join bond_changes
        on bond_changes.day = rune_prices.day
    left join node_changes
        on node_changes.day = rune_prices.day
),

-- Average number of Active nodes over the day, weighted by time in seconds, as Midgard's earnings
-- history computes it. The last indexed day is averaged up to its last block.
day_spans as (
    select
        day,
        active_nodes - coalesce(day_change.active_node_change, 0) as start_active_nodes,
        extract(epoch from day::timestamp)::bigint as start_second,
        least(
            extract(epoch from (day + 1)::timestamp)::bigint,
            (select floor(extract(epoch from block_time))::bigint from {{ ref('core__blocks') }} order by block_height desc limit 1)
        ) as end_second
    from running
    left join node_changes as day_change
        using (day)
),

node_steps as (
    select
        changes.day,
        floor(extract(epoch from changes.block_time))::bigint as change_second,
        day_spans.start_active_nodes + sum(changes.active_node_change) over (
            partition by changes.day order by changes.block_time, changes.event_id rows between unbounded preceding and current row
        ) as active_nodes_after,
        coalesce(
            lead(floor(extract(epoch from changes.block_time))::bigint) over (partition by changes.day order by changes.block_time, changes.event_id),
            day_spans.end_second
        ) as next_second
    from {{ ref('core__node_status_changes') }} as changes
    inner join day_spans
        on day_spans.day = changes.day
    where changes.active_node_change <> 0
    {%- if is_incremental() %}
        and changes.block_height >= {{ since_block }}
    {%- endif %}
),

average_nodes as (
    select
        day_spans.day,
        (
            day_spans.start_active_nodes * (coalesce(min(node_steps.change_second), day_spans.end_second) - day_spans.start_second)
            + coalesce(sum(node_steps.active_nodes_after * (node_steps.next_second - node_steps.change_second)), 0)
        )::numeric / nullif(day_spans.end_second - day_spans.start_second, 0) as average_active_nodes
    from day_spans
    left join node_steps
        on node_steps.day = day_spans.day
    group by day_spans.day, day_spans.start_active_nodes, day_spans.start_second, day_spans.end_second
)

select
    running.day,
    running.rune_price_usd,
    coalesce(swaps.swap_count, 0) as swap_count,
    coalesce(swaps.unique_swappers, 0) as unique_swappers,
    coalesce(swaps.user_volume_usd, 0) as user_volume_usd,
    {{ units('coalesce(swap_legs.swap_volume_e8, 0)') }} as swap_volume,
    coalesce(swap_legs.swap_volume_e8, 0) as swap_volume_e8,
    coalesce(swap_legs.swap_volume_usd, 0) as swap_volume_usd,
    {{ units('coalesce(earnings.liquidity_fee_e8, 0)') }} as liquidity_fee,
    coalesce(earnings.liquidity_fee_e8, 0) as liquidity_fee_e8,
    coalesce(earnings.liquidity_fee_usd, 0) as liquidity_fee_usd,
    {{ units('coalesce(earnings.pool_rewards_e8, 0)') }} as pool_rewards,
    coalesce(earnings.pool_rewards_e8, 0) as pool_rewards_e8,
    coalesce(earnings.pool_rewards_usd, 0) as pool_rewards_usd,
    {{ units('coalesce(earnings.bond_rewards_e8, 0)') }} as bond_rewards,
    coalesce(earnings.bond_rewards_e8, 0) as bond_rewards_e8,
    coalesce(earnings.bond_rewards_usd, 0) as bond_rewards_usd,
    {{ units('coalesce(earnings.block_rewards_e8, 0)') }} as block_rewards,
    coalesce(earnings.block_rewards_e8, 0) as block_rewards_e8,
    coalesce(earnings.block_rewards_usd, 0) as block_rewards_usd,
    {{ units('coalesce(earnings.liquidity_earnings_e8, 0)') }} as liquidity_earnings,
    coalesce(earnings.liquidity_earnings_e8, 0) as liquidity_earnings_e8,
    coalesce(earnings.liquidity_earnings_usd, 0) as liquidity_earnings_usd,
    {{ units('coalesce(earnings.earnings_e8, 0)') }} as earnings,
    coalesce(earnings.earnings_e8, 0) as earnings_e8,
    coalesce(earnings.earnings_usd, 0) as earnings_usd,
    {{ units('running.total_value_pooled_e8') }} as total_value_pooled,
    running.total_value_pooled_e8,
    {{ units('running.total_value_pooled_e8') }} * running.rune_price_usd as total_value_pooled_usd,
    {{ units('running.total_value_bonded_e8') }} as total_value_bonded,
    running.total_value_bonded_e8,
    {{ units('running.total_value_bonded_e8') }} * running.rune_price_usd as total_value_bonded_usd,
    {{ units('running.total_value_pooled_e8 + running.total_value_bonded_e8') }} as total_value_locked,
    running.total_value_pooled_e8 + running.total_value_bonded_e8 as total_value_locked_e8,
    {{ units('running.total_value_pooled_e8 + running.total_value_bonded_e8') }} * running.rune_price_usd as total_value_locked_usd,
    running.active_nodes,
    round(average_nodes.average_active_nodes, 2) as average_active_nodes
from running
left join average_nodes
    on average_nodes.day = running.day
left join swaps
    on swaps.day = running.day
left join swap_legs
    on swap_legs.day = running.day
left join earnings
    on earnings.day = running.day
