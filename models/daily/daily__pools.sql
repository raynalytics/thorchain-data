with last_indexed_day as (
    select max(day) as day from {{ ref('core__blocks') }}
),

end_of_day_depths as (
    select distinct on (pool, day)
        pool,
        day,
        asset_depth_e8,
        rune_depth_e8,
        synth_depth_e8
    from {{ ref('core__pool_depths') }}
    order by pool, day, block_height desc
),

-- A pool gets a row for every day from its first depth record. Pools whose depths fell to zero
-- stop on their last recorded day; all others run to the last indexed day.
pool_days as (
    select
        pool,
        generate_series(
            min(day),
            case
                when (array_agg(asset_depth_e8 + rune_depth_e8 order by day desc))[1] > 0
                    then (select day from last_indexed_day)
                else max(day)
            end,
            interval '1 day'
        )::date as day
    from end_of_day_depths
    group by pool
),

swap_legs as (
    select
        day,
        pool,
        count(distinct from_address) as unique_swappers,
        sum(swap_volume_e8)::bigint as swap_volume_e8,
        sum(swap_volume_usd) as swap_volume_usd,
        sum(liquidity_fee_e8)::bigint as liquidity_fee_e8,
        sum(liquidity_fee_usd) as liquidity_fee_usd
    from {{ ref('core__swap_legs') }}
    group by day, pool
),

swap_counts as (
    select
        swaps.day,
        legs.pool,
        count(distinct legs.tx_id) as swap_count
    from {{ ref('core__swap_legs') }} as legs
    inner join {{ ref('core__swaps') }} as swaps
        on swaps.tx_id = legs.tx_id
    group by swaps.day, legs.pool
),

pool_rewards as (
    select
        (rewards.block_time at time zone 'UTC')::date as day,
        rewards.pool,
        sum(rewards.pool_rewards_e8)::bigint as pool_rewards_e8,
        sum(rewards.pool_rewards * prices.rune_price_usd) as pool_rewards_usd
    from {{ ref('events__pool_rewards') }} as rewards
    left join {{ ref('core__rune_price') }} as prices
        on prices.block_height = rewards.block_height
    group by 1, 2
),

liquidity as (
    select
        day,
        pool,
        count(*) filter (where action = 'add') as add_count,
        coalesce(sum(rune_amount_e8) filter (where action = 'add'), 0)::bigint as rune_added_e8,
        coalesce(sum(rune_amount_usd) filter (where action = 'add'), 0) as rune_added_usd,
        coalesce(sum(asset_amount_e8) filter (where action = 'add'), 0)::bigint as asset_added_e8,
        coalesce(sum(asset_amount_usd) filter (where action = 'add'), 0) as asset_added_usd,
        count(*) filter (where action = 'withdraw') as withdraw_count,
        coalesce(sum(rune_amount_e8) filter (where action = 'withdraw'), 0)::bigint as rune_withdrawn_e8,
        coalesce(sum(rune_amount_usd) filter (where action = 'withdraw'), 0) as rune_withdrawn_usd,
        coalesce(sum(asset_amount_e8) filter (where action = 'withdraw'), 0)::bigint as asset_withdrawn_e8,
        coalesce(sum(asset_amount_usd) filter (where action = 'withdraw'), 0) as asset_withdrawn_usd,
        coalesce(sum(impermanent_loss_protection_e8), 0)::bigint as impermanent_loss_protection_e8,
        coalesce(sum(impermanent_loss_protection_usd), 0) as impermanent_loss_protection_usd,
        sum(liquidity_units_change)::bigint as liquidity_units_change
    from {{ ref('core__liquidity_actions') }}
    group by day, pool
),

rune_prices as (
    {{ end_of_day_rune_price() }}
),

carried as (
    select
        pool_days.day,
        pool_days.pool,
        end_of_day_depths.asset_depth_e8,
        end_of_day_depths.rune_depth_e8,
        end_of_day_depths.synth_depth_e8,
        count(end_of_day_depths.day) over (partition by pool_days.pool order by pool_days.day) as depth_group,
        sum(coalesce(liquidity.liquidity_units_change, 0))
            over (partition by pool_days.pool order by pool_days.day)::bigint as liquidity_units
    from pool_days
    left join end_of_day_depths
        on end_of_day_depths.pool = pool_days.pool
        and end_of_day_depths.day = pool_days.day
    left join liquidity
        on liquidity.pool = pool_days.pool
        and liquidity.day = pool_days.day
),

depths as (
    select
        day,
        pool,
        first_value(asset_depth_e8) over (partition by pool, depth_group order by day) as asset_depth_e8,
        first_value(rune_depth_e8) over (partition by pool, depth_group order by day) as rune_depth_e8,
        first_value(synth_depth_e8) over (partition by pool, depth_group order by day) as synth_depth_e8,
        liquidity_units
    from carried
)

select
    depths.day,
    depths.pool,
    {{ units('depths.asset_depth_e8') }} as asset_depth,
    depths.asset_depth_e8,
    {{ units('depths.rune_depth_e8') }} as rune_depth,
    depths.rune_depth_e8,
    {{ units('depths.synth_depth_e8') }} as synth_depth,
    depths.synth_depth_e8,
    depths.rune_depth_e8::numeric / nullif(depths.asset_depth_e8, 0) as asset_price,
    depths.rune_depth_e8::numeric / nullif(depths.asset_depth_e8, 0) * rune_prices.rune_price_usd as asset_price_usd,
    {{ units('2 * depths.rune_depth_e8') }} as total_value_pooled,
    2 * depths.rune_depth_e8 as total_value_pooled_e8,
    {{ units('2 * depths.rune_depth_e8') }} * rune_prices.rune_price_usd as total_value_pooled_usd,
    depths.liquidity_units,
    coalesce(swap_counts.swap_count, 0) as swap_count,
    coalesce(swap_legs.unique_swappers, 0) as unique_swappers,
    {{ units('coalesce(swap_legs.swap_volume_e8, 0)') }} as swap_volume,
    coalesce(swap_legs.swap_volume_e8, 0) as swap_volume_e8,
    coalesce(swap_legs.swap_volume_usd, 0) as swap_volume_usd,
    {{ units('coalesce(swap_legs.liquidity_fee_e8, 0)') }} as liquidity_fee,
    coalesce(swap_legs.liquidity_fee_e8, 0) as liquidity_fee_e8,
    coalesce(swap_legs.liquidity_fee_usd, 0) as liquidity_fee_usd,
    {{ units('coalesce(pool_rewards.pool_rewards_e8, 0)') }} as pool_rewards,
    coalesce(pool_rewards.pool_rewards_e8, 0) as pool_rewards_e8,
    coalesce(pool_rewards.pool_rewards_usd, 0) as pool_rewards_usd,
    coalesce(liquidity.add_count, 0) as add_count,
    {{ units('coalesce(liquidity.rune_added_e8, 0)') }} as rune_added,
    coalesce(liquidity.rune_added_e8, 0) as rune_added_e8,
    coalesce(liquidity.rune_added_usd, 0) as rune_added_usd,
    {{ units('coalesce(liquidity.asset_added_e8, 0)') }} as asset_added,
    coalesce(liquidity.asset_added_e8, 0) as asset_added_e8,
    coalesce(liquidity.asset_added_usd, 0) as asset_added_usd,
    coalesce(liquidity.withdraw_count, 0) as withdraw_count,
    {{ units('coalesce(liquidity.rune_withdrawn_e8, 0)') }} as rune_withdrawn,
    coalesce(liquidity.rune_withdrawn_e8, 0) as rune_withdrawn_e8,
    coalesce(liquidity.rune_withdrawn_usd, 0) as rune_withdrawn_usd,
    {{ units('coalesce(liquidity.asset_withdrawn_e8, 0)') }} as asset_withdrawn,
    coalesce(liquidity.asset_withdrawn_e8, 0) as asset_withdrawn_e8,
    coalesce(liquidity.asset_withdrawn_usd, 0) as asset_withdrawn_usd,
    {{ units('coalesce(liquidity.impermanent_loss_protection_e8, 0)') }} as impermanent_loss_protection,
    coalesce(liquidity.impermanent_loss_protection_e8, 0) as impermanent_loss_protection_e8,
    coalesce(liquidity.impermanent_loss_protection_usd, 0) as impermanent_loss_protection_usd
from depths
left join rune_prices
    on rune_prices.day = depths.day
left join swap_legs
    on swap_legs.pool = depths.pool
    and swap_legs.day = depths.day
left join swap_counts
    on swap_counts.pool = depths.pool
    and swap_counts.day = depths.day
left join pool_rewards
    on pool_rewards.pool = depths.pool
    and pool_rewards.day = depths.day
left join liquidity
    on liquidity.pool = depths.pool
    and liquidity.day = depths.day
