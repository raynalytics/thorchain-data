with rune_prices as (
    {{ end_of_day_rune_price() }}
),

swaps as (
    select
        day,
        count(*) as swap_count,
        count(distinct from_address) as unique_swappers,
        sum(user_volume_usd) as user_volume_usd
    from {{ ref('core__swaps') }}
    group by day
),

swap_legs as (
    select
        day,
        sum(swap_volume_e8)::bigint as swap_volume_e8,
        sum(swap_volume_usd) as swap_volume_usd
    from {{ ref('core__swap_legs') }}
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
    group by day
),

pooled as (
    select
        day,
        sum(total_value_pooled_e8)::bigint as total_value_pooled_e8
    from {{ ref('daily__pools') }}
    group by day
),

bond_changes as (
    select
        (block_time at time zone 'UTC')::date as day,
        sum(bond_change_e8) as bond_change_e8
    from {{ ref('events__bonds') }}
    group by 1
),

node_changes as (
    select
        day,
        sum(active_node_change) as active_node_change
    from {{ ref('core__node_status_changes') }}
    group by day
),

-- Bonded RUNE and active nodes are running totals of their changes, as Midgard computes them.
running as (
    select
        rune_prices.day,
        rune_prices.rune_price_usd,
        coalesce(pooled.total_value_pooled_e8, 0) as total_value_pooled_e8,
        sum(coalesce(bond_changes.bond_change_e8, 0)) over (order by rune_prices.day)::bigint as total_value_bonded_e8,
        sum(coalesce(node_changes.active_node_change, 0)) over (order by rune_prices.day)::bigint as active_nodes
    from rune_prices
    left join pooled
        on pooled.day = rune_prices.day
    left join bond_changes
        on bond_changes.day = rune_prices.day
    left join node_changes
        on node_changes.day = rune_prices.day
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
    running.active_nodes
from running
left join swaps
    on swaps.day = running.day
left join swap_legs
    on swap_legs.day = running.day
left join earnings
    on earnings.day = running.day
