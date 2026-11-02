with swap_affiliates as (
    select distinct
        swaps.day,
        named.affiliate,
        swaps.tx_id,
        swaps.from_address,
        swaps.user_volume_usd,
        swaps.swap_volume_usd
    from {{ ref('core__swaps') }} as swaps
    cross join lateral unnest(swaps.affiliates) as named (affiliate)
    where named.affiliate is not null
),

swap_stats as (
    select
        day,
        affiliate,
        count(*) as swap_count,
        count(distinct from_address) as unique_swappers,
        sum(user_volume_usd) as user_volume_usd,
        sum(swap_volume_usd) as swap_volume_usd
    from swap_affiliates
    group by day, affiliate
),

fee_stats as (
    select
        day,
        affiliate,
        count(*) as fee_payment_count,
        sum(affiliate_fee_e8)::bigint as affiliate_fee_e8,
        sum(affiliate_fee_usd) as affiliate_fee_usd
    from {{ ref('core__affiliate_fees') }}
    group by day, affiliate
)

select
    coalesce(swap_stats.day, fee_stats.day) as day,
    coalesce(swap_stats.affiliate, fee_stats.affiliate) as affiliate,
    coalesce(swap_stats.swap_count, 0) as swap_count,
    coalesce(swap_stats.unique_swappers, 0) as unique_swappers,
    coalesce(swap_stats.user_volume_usd, 0) as user_volume_usd,
    coalesce(swap_stats.swap_volume_usd, 0) as swap_volume_usd,
    coalesce(fee_stats.fee_payment_count, 0) as fee_payment_count,
    {{ units('coalesce(fee_stats.affiliate_fee_e8, 0)') }} as affiliate_fee,
    coalesce(fee_stats.affiliate_fee_e8, 0) as affiliate_fee_e8,
    coalesce(fee_stats.affiliate_fee_usd, 0) as affiliate_fee_usd
from swap_stats
full outer join fee_stats
    on fee_stats.day = swap_stats.day
    and fee_stats.affiliate = swap_stats.affiliate
