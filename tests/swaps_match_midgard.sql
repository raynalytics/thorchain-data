-- Daily swap leg count, swap volume and liquidity fees must equal Midgard's own daily swap
-- aggregate (midgard_agg.swaps_day, which serves Midgard's /history/swaps API) for every completed day.
-- Midgard counts swap legs, so the count compared is legs, not user swaps.
with ours as (
    select
        day,
        count(*) as leg_count,
        sum(swap_volume_e8) as swap_volume_e8,
        sum(liquidity_fee_e8) as liquidity_fees_e8
    from {{ ref('core__swap_legs') }}
    group by day
),

midgard as (
    select
        {{ block_day('aggregate_timestamp') }} as day,
        sum(swap_count) as leg_count,
        sum(volume_e8) as swap_volume_e8,
        sum(liq_fee_in_rune_e8) as liquidity_fees_e8
    from {{ source('midgard_agg', 'swaps_day') }}
    group by 1
)

select
    coalesce(ours.day, midgard.day) as day,
    ours.leg_count,
    midgard.leg_count as midgard_leg_count,
    ours.swap_volume_e8,
    midgard.swap_volume_e8 as midgard_swap_volume_e8,
    ours.liquidity_fees_e8,
    midgard.liquidity_fees_e8 as midgard_liquidity_fees_e8
from ours
full outer join midgard
    on midgard.day = ours.day
where coalesce(ours.day, midgard.day) < (select max(day) from {{ ref('core__blocks') }})
    and (
        ours.leg_count is distinct from midgard.leg_count
        or ours.swap_volume_e8 is distinct from midgard.swap_volume_e8
        or ours.liquidity_fees_e8 is distinct from midgard.liquidity_fees_e8
    )
