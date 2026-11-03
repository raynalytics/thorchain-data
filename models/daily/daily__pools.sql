{{ config(
    materialized='incremental',
    unique_key=['day', 'pool'],
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['day', 'pool'], 'unique': true}, {'columns': ['pool', 'day']}]
) }}

{%- if is_incremental() %}
{%- set start_day = daily_start_day() %}
{%- set since_block = first_block_of("date '" ~ start_day ~ "'") %}
{%- endif %}

-- A pool gets a row for every day from its first depth record. Pools whose depths fell to zero
-- stop on their last recorded day; all others run to the last indexed day. An incremental run
-- recomputes each pool from daily_start_day(), or from the day after its last row if it had stopped
-- earlier, carrying depths and liquidity units on from that row.
with last_indexed_day as (
    select day from {{ ref('core__blocks') }} order by block_height desc limit 1
),

pool_starts as (
    {%- if is_incremental() %}
    select
        pool,
        day + 1 as start_day,
        asset_depth_e8,
        rune_depth_e8,
        synth_depth_e8,
        liquidity_units,
        status,
        liquidity_providers
    from (
        select distinct on (pool) *
        from {{ this }}
        where day < date '{{ start_day }}'
        order by pool, day desc
    ) as previous_rows

    union all

    select pool, min(day), null, null, null, 0, null, null
    from {{ ref('core__pool_depths') }}
    where block_height >= {{ since_block }}
        and pool not in (select pool from {{ this }} where day < date '{{ start_day }}')
    group by pool
    {%- else %}
    select pool, min(day) as start_day, null::bigint as asset_depth_e8, null::bigint as rune_depth_e8,
        null::bigint as synth_depth_e8, 0::bigint as liquidity_units, null::text as status,
        null::bigint as liquidity_providers
    from {{ ref('core__pool_depths') }}
    group by pool
    {%- endif %}
),

end_of_day_depths as (
    select distinct on (depths.pool, depths.day)
        depths.pool,
        depths.day,
        depths.asset_depth_e8,
        depths.rune_depth_e8,
        depths.synth_depth_e8
    from {{ ref('core__pool_depths') }} as depths
    inner join pool_starts
        on pool_starts.pool = depths.pool
        and depths.block_height >= {{ first_block_of('pool_starts.start_day') }}
    order by depths.pool, depths.day, depths.block_height desc
),

-- Pool status and liquidity provider count at the end of each day they changed. The provider count is
-- Midgard's own (midgard_agg.members_count): addresses with liquidity units or pending liquidity in the pool.
end_of_day_status as (
    select distinct on (changes.pool, changes.day)
        changes.pool,
        changes.day,
        changes.status
    from (
        select pool, (block_time at time zone 'UTC')::date as day, status, event_id
        from {{ ref('events__pool_status_changes') }}
    ) as changes
    inner join pool_starts
        on pool_starts.pool = changes.pool
        and changes.day >= pool_starts.start_day
    order by changes.pool, changes.day, changes.event_id desc
),

end_of_day_providers as (
    select distinct on (counts.pool, (to_timestamp(counts.block_timestamp / 1e9) at time zone 'UTC')::date)
        counts.pool,
        (to_timestamp(counts.block_timestamp / 1e9) at time zone 'UTC')::date as day,
        counts.count as liquidity_providers
    from {{ source('midgard_agg', 'members_count') }} as counts
    inner join pool_starts
        on pool_starts.pool = counts.pool
        and counts.block_timestamp >= {{ day_start_ns('pool_starts.start_day') }}
    order by counts.pool, (to_timestamp(counts.block_timestamp / 1e9) at time zone 'UTC')::date, counts.block_timestamp desc
),

pool_days as (
    select
        pool_starts.pool,
        generate_series(
            pool_starts.start_day,
            case
                when latest.asset_depth_e8 + latest.rune_depth_e8 > 0 then (select day from last_indexed_day)
                else latest.day
            end,
            interval '1 day'
        )::date as day
    from pool_starts
    cross join lateral (
        select depths.day, depths.asset_depth_e8, depths.rune_depth_e8
        from {{ ref('core__pool_depths') }} as depths
        where depths.pool = pool_starts.pool
        order by depths.block_height desc
        limit 1
    ) as latest
),

swap_legs as (
    select
        day,
        pool,
        count(distinct from_address) filter (where leg_type = 'user') as unique_swappers,
        sum(swap_volume_e8)::bigint as swap_volume_e8,
        sum(swap_volume_usd) as swap_volume_usd,
        sum(liquidity_fee_e8)::bigint as liquidity_fee_e8,
        sum(liquidity_fee_usd) as liquidity_fee_usd,
        -- Split by direction as Midgard's pool history does: legs paying out the asset (RUNE in) and
        -- legs paying out RUNE (asset in). Synth, trade and secured asset legs count with their pool.
        count(*) filter (where direction like 'rune_to_%') as to_asset_leg_count,
        count(*) filter (where direction like '%_to_rune') as to_rune_leg_count,
        coalesce(sum(swap_volume_e8) filter (where direction like 'rune_to_%'), 0)::bigint as to_asset_swap_volume_e8,
        coalesce(sum(swap_volume_usd) filter (where direction like 'rune_to_%'), 0) as to_asset_swap_volume_usd,
        coalesce(sum(swap_volume_e8) filter (where direction like '%_to_rune'), 0)::bigint as to_rune_swap_volume_e8,
        coalesce(sum(swap_volume_usd) filter (where direction like '%_to_rune'), 0) as to_rune_swap_volume_usd,
        coalesce(sum(liquidity_fee_e8) filter (where direction like 'rune_to_%'), 0)::bigint as to_asset_liquidity_fee_e8,
        coalesce(sum(liquidity_fee_usd) filter (where direction like 'rune_to_%'), 0) as to_asset_liquidity_fee_usd,
        coalesce(sum(liquidity_fee_e8) filter (where direction like '%_to_rune'), 0)::bigint as to_rune_liquidity_fee_e8,
        coalesce(sum(liquidity_fee_usd) filter (where direction like '%_to_rune'), 0) as to_rune_liquidity_fee_usd,
        round(avg(swap_slip_bps), 2) as average_slip_bps,
        round(avg(swap_slip_bps) filter (where direction like 'rune_to_%'), 2) as to_asset_average_slip_bps,
        round(avg(swap_slip_bps) filter (where direction like '%_to_rune'), 2) as to_rune_average_slip_bps
    from {{ ref('core__swap_legs') }}
    {%- if is_incremental() %}
    where block_height >= {{ since_block }}
    {%- endif %}
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
    where legs.leg_type = 'user'
    {%- if is_incremental() %}
        and legs.block_height >= {{ since_block }}
        and swaps.day >= date '{{ start_day }}'
    {%- endif %}
    group by swaps.day, legs.pool
),

pool_rewards as (
    select
        (rewards.block_time at time zone 'UTC')::date as day,
        rewards.pool,
        sum(rewards.pool_rewards_e8)::bigint as pool_rewards_e8,
        sum(rewards.pool_rewards * prices.rune_price_usd) as pool_rewards_usd
    {%- if is_incremental() %}
    from ({{ events__pool_rewards_sql(midgard_rows(
        'rewards_event_entries', 'block_timestamp >= ' ~ day_start_ns("date '" ~ start_day ~ "'")
    )) }}) as rewards
    {%- else %}
    from {{ ref('events__pool_rewards') }} as rewards
    {%- endif %}
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
    {%- if is_incremental() %}
    where block_height >= {{ since_block }}
    {%- endif %}
    group by day, pool
),

rune_prices as (
    {%- if is_incremental() %}
    {{ end_of_day_rune_price(start_day) }}
    {%- else %}
    {{ end_of_day_rune_price() }}
    {%- endif %}
),

-- Each pool's days, plus the day before its first recomputed day carrying the stored depths and units.
series as (
    select
        pool_days.pool,
        pool_days.day,
        end_of_day_depths.asset_depth_e8,
        end_of_day_depths.rune_depth_e8,
        end_of_day_depths.synth_depth_e8,
        end_of_day_depths.day is not null as has_depths,
        coalesce(liquidity.liquidity_units_change, 0) as liquidity_units_change,
        end_of_day_status.status,
        end_of_day_status.day is not null as has_status,
        end_of_day_providers.liquidity_providers,
        end_of_day_providers.day is not null as has_providers
    from pool_days
    left join end_of_day_depths
        on end_of_day_depths.pool = pool_days.pool
        and end_of_day_depths.day = pool_days.day
    left join liquidity
        on liquidity.pool = pool_days.pool
        and liquidity.day = pool_days.day
    left join end_of_day_status
        on end_of_day_status.pool = pool_days.pool
        and end_of_day_status.day = pool_days.day
    left join end_of_day_providers
        on end_of_day_providers.pool = pool_days.pool
        and end_of_day_providers.day = pool_days.day

    union all

    select
        pool, start_day - 1, asset_depth_e8, rune_depth_e8, synth_depth_e8, true, liquidity_units,
        status, status is not null, liquidity_providers, liquidity_providers is not null
    from pool_starts
    where asset_depth_e8 is not null
),

carried as (
    select
        *,
        count(*) filter (where has_depths) over (partition by pool order by day) as depth_group,
        count(*) filter (where has_status) over (partition by pool order by day) as status_group,
        count(*) filter (where has_providers) over (partition by pool order by day) as providers_group,
        sum(liquidity_units_change) over (partition by pool order by day)::bigint as liquidity_units
    from series
),

depths as (
    select
        carried.day,
        carried.pool,
        first_value(carried.asset_depth_e8) over (partition by carried.pool, carried.depth_group order by carried.day) as asset_depth_e8,
        first_value(carried.rune_depth_e8) over (partition by carried.pool, carried.depth_group order by carried.day) as rune_depth_e8,
        first_value(carried.synth_depth_e8) over (partition by carried.pool, carried.depth_group order by carried.day) as synth_depth_e8,
        carried.liquidity_units,
        first_value(carried.status) over (partition by carried.pool, carried.status_group order by carried.day) as status,
        coalesce(
            first_value(carried.liquidity_providers) over (partition by carried.pool, carried.providers_group order by carried.day),
            0
        ) as liquidity_providers,
        carried.day >= pool_starts.start_day as is_new
    from carried
    inner join pool_starts
        on pool_starts.pool = carried.pool
),

-- Days before the start day only occur for a pool that had stopped and was filled again; they take
-- the last RUNE price of the day directly.
day_prices as (
    select distinct
        depths.day,
        coalesce(rune_prices.rune_price_usd, (
            select prices.rune_price_usd
            from {{ ref('core__rune_price') }} as prices
            where prices.block_height < {{ first_block_of('depths.day + 1') }}
                and prices.rune_price_usd is not null
            order by prices.block_height desc
            limit 1
        )) as rune_price_usd
    from depths
    left join rune_prices
        on rune_prices.day = depths.day
    where depths.is_new
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
    synth_units.synth_units,
    depths.liquidity_units + synth_units.synth_units as pool_units,
    sqrt(depths.asset_depth_e8::numeric * depths.rune_depth_e8)
        / nullif(depths.liquidity_units + synth_units.synth_units, 0) as liquidity_unit_value_index,
    depths.liquidity_providers,
    depths.status,
    coalesce(swap_counts.swap_count, 0) as swap_count,
    coalesce(swap_legs.unique_swappers, 0) as unique_swappers,
    {{ units('coalesce(swap_legs.swap_volume_e8, 0)') }} as swap_volume,
    coalesce(swap_legs.swap_volume_e8, 0) as swap_volume_e8,
    coalesce(swap_legs.swap_volume_usd, 0) as swap_volume_usd,
    {{ units('coalesce(swap_legs.liquidity_fee_e8, 0)') }} as liquidity_fee,
    coalesce(swap_legs.liquidity_fee_e8, 0) as liquidity_fee_e8,
    coalesce(swap_legs.liquidity_fee_usd, 0) as liquidity_fee_usd,
    coalesce(swap_legs.to_asset_leg_count, 0) as to_asset_leg_count,
    coalesce(swap_legs.to_rune_leg_count, 0) as to_rune_leg_count,
    {{ units('coalesce(swap_legs.to_asset_swap_volume_e8, 0)') }} as to_asset_swap_volume,
    coalesce(swap_legs.to_asset_swap_volume_e8, 0) as to_asset_swap_volume_e8,
    coalesce(swap_legs.to_asset_swap_volume_usd, 0) as to_asset_swap_volume_usd,
    {{ units('coalesce(swap_legs.to_rune_swap_volume_e8, 0)') }} as to_rune_swap_volume,
    coalesce(swap_legs.to_rune_swap_volume_e8, 0) as to_rune_swap_volume_e8,
    coalesce(swap_legs.to_rune_swap_volume_usd, 0) as to_rune_swap_volume_usd,
    {{ units('coalesce(swap_legs.to_asset_liquidity_fee_e8, 0)') }} as to_asset_liquidity_fee,
    coalesce(swap_legs.to_asset_liquidity_fee_e8, 0) as to_asset_liquidity_fee_e8,
    coalesce(swap_legs.to_asset_liquidity_fee_usd, 0) as to_asset_liquidity_fee_usd,
    {{ units('coalesce(swap_legs.to_rune_liquidity_fee_e8, 0)') }} as to_rune_liquidity_fee,
    coalesce(swap_legs.to_rune_liquidity_fee_e8, 0) as to_rune_liquidity_fee_e8,
    coalesce(swap_legs.to_rune_liquidity_fee_usd, 0) as to_rune_liquidity_fee_usd,
    swap_legs.average_slip_bps,
    swap_legs.to_asset_average_slip_bps,
    swap_legs.to_rune_average_slip_bps,
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
-- Synth units as Midgard computes them: liquidity units x synth supply / (2 x asset depth - synth supply).
cross join lateral (
    select case
        when depths.asset_depth_e8 = 0 or 2 * depths.asset_depth_e8 = depths.synth_depth_e8 then 0
        else trunc(depths.liquidity_units::numeric * depths.synth_depth_e8 / (2 * depths.asset_depth_e8 - depths.synth_depth_e8))::bigint
    end as synth_units
) as synth_units
left join day_prices as rune_prices
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
where depths.is_new
