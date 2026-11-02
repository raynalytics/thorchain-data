-- Same definitions as Midgard's earnings history: liquidity fees from swaps, block rewards split
-- between pools and bonded nodes, and earnings as their sum.
with per_block as (
    select block_height, liquidity_fee_e8 as liquidity_fee_e8, 0::bigint as pool_rewards_e8, 0::bigint as bond_rewards_e8
    from {{ ref('core__swap_legs') }}

    union all

    select block_height, 0, pool_rewards_e8, 0
    from {{ ref('events__pool_rewards') }}

    union all

    select block_height, 0, 0, bond_rewards_e8
    from {{ ref('events__rewards') }}
),

totals as (
    select
        block_height,
        sum(liquidity_fee_e8)::bigint as liquidity_fee_e8,
        sum(pool_rewards_e8)::bigint as pool_rewards_e8,
        sum(bond_rewards_e8)::bigint as bond_rewards_e8
    from per_block
    group by block_height
),

derived as (
    select
        totals.*,
        pool_rewards_e8 + bond_rewards_e8 as block_rewards_e8,
        liquidity_fee_e8 + pool_rewards_e8 as liquidity_earnings_e8,
        liquidity_fee_e8 + pool_rewards_e8 + bond_rewards_e8 as earnings_e8
    from totals
)

select
    derived.block_height,
    blocks.block_time,
    blocks.day,
    {{ units('liquidity_fee_e8') }} as liquidity_fee,
    liquidity_fee_e8,
    {{ units('liquidity_fee_e8') }} * prices.rune_price_usd as liquidity_fee_usd,
    {{ units('pool_rewards_e8') }} as pool_rewards,
    pool_rewards_e8,
    {{ units('pool_rewards_e8') }} * prices.rune_price_usd as pool_rewards_usd,
    {{ units('bond_rewards_e8') }} as bond_rewards,
    bond_rewards_e8,
    {{ units('bond_rewards_e8') }} * prices.rune_price_usd as bond_rewards_usd,
    {{ units('block_rewards_e8') }} as block_rewards,
    block_rewards_e8,
    {{ units('block_rewards_e8') }} * prices.rune_price_usd as block_rewards_usd,
    {{ units('liquidity_earnings_e8') }} as liquidity_earnings,
    liquidity_earnings_e8,
    {{ units('liquidity_earnings_e8') }} * prices.rune_price_usd as liquidity_earnings_usd,
    {{ units('earnings_e8') }} as earnings,
    earnings_e8,
    {{ units('earnings_e8') }} * prices.rune_price_usd as earnings_usd,
    prices.rune_price_usd
from derived
inner join {{ ref('core__blocks') }} as blocks
    on blocks.block_height = derived.block_height
left join {{ ref('core__rune_price') }} as prices
    on prices.block_height = derived.block_height
