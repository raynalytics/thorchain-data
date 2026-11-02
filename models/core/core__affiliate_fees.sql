with recorded as (
    select
        fees.event_id,
        {{ block_height('fees.event_id') }} as block_height,
        {{ block_time('fees.block_timestamp') }} as block_time,
        {{ block_day('fees.block_timestamp') }} as day,
        fees.tx_id,
        coalesce(nullif(fees.thorname, ''), fees.rune_address) as affiliate,
        nullif(fees.thorname, '') as thorname,
        fees.rune_address as affiliate_address,
        fees.fee_bps as affiliate_fee_bps,
        fees.asset,
        fees.gross_amt as gross_amount_e8,
        fees.fee_amt as fee_amount_e8,
        fees._fee_amt_in_rune as affiliate_fee_e8,
        {{ units('fees._fee_amt_in_rune') }} * prices.rune_price_usd as affiliate_fee_usd,
        fees.memo,
        false as is_estimated
    from {{ source('midgard', 'affiliate_fee_events') }} as fees
    left join {{ ref('core__rune_price') }} as prices
        on prices.block_height = {{ block_height('fees.event_id') }}
),

-- User swaps that started before affiliate fee events exist, with their input amount and value.
swap_inputs as (
    select
        legs.tx_id,
        min(legs.event_id) as event_id,
        min(legs.block_height) as block_height,
        min(legs.block_time) as block_time,
        firsts.from_asset,
        firsts.memo,
        sum(legs.from_amount_e8) filter (where legs.from_asset = firsts.from_asset) as from_amount_e8,
        sum(legs.swap_volume_e8) filter (where legs.from_asset = firsts.from_asset) as input_value_e8,
        sum(legs.from_amount_usd) filter (where legs.from_asset = firsts.from_asset) as input_value_usd
    from {{ ref('core__swap_legs') }} as legs
    inner join (
        select distinct on (tx_id)
            tx_id,
            event_id,
            from_asset,
            memo
        from {{ ref('core__swap_legs') }}
        where leg_type = 'user'
        order by tx_id, event_id
    ) as firsts
        on firsts.tx_id = legs.tx_id
    where legs.leg_type = 'user'
        and firsts.event_id < coalesce((select min(event_id) from recorded), 9223372036854775807)
        and not exists (select 1 from recorded where recorded.tx_id = legs.tx_id)
    group by legs.tx_id, firsts.from_asset, firsts.memo
),

-- Before affiliate fee events exist, THORChain skimmed the fee from the input and swapped it to RUNE
-- in a leg of its own (one per transaction); the RUNE it produced is the fee paid.
fee_legs as (
    select
        tx_id,
        event_id,
        block_height,
        block_time,
        from_amount_e8,
        to_amount_e8,
        to_amount_usd
    from {{ ref('core__swap_legs') }}
    where leg_type = 'affiliate_fee'
        and tx_id in (select tx_id from swap_inputs)
),

-- The memo lists affiliates and their basis points, separated by '/'.
memo_affiliates as (
    select
        swaps.*,
        named.affiliate,
        case
            when split_part({{ swap_memo_field('swaps.memo', 6) }}, '/', named.position::int) ~ '^\d{1,5}$'
                then split_part({{ swap_memo_field('swaps.memo', 6) }}, '/', named.position::int)::bigint
        end as affiliate_fee_bps
    from swap_inputs as swaps
    cross join lateral unnest(string_to_array({{ swap_memo_field('swaps.memo', 5) }}, '/'))
        with ordinality as named (affiliate, position)
    where named.affiliate <> ''
),

memo_fees as (
    select
        tx_id,
        affiliate,
        sum(affiliate_fee_bps) as affiliate_fee_bps,
        sum(sum(affiliate_fee_bps)) over (partition by tx_id) as total_fee_bps,
        min(event_id) as swap_event_id,
        min(block_height) as swap_block_height,
        min(block_time) as swap_block_time,
        min(from_asset) as from_asset,
        min(from_amount_e8) as from_amount_e8,
        min(input_value_e8) as input_value_e8,
        min(input_value_usd) as input_value_usd,
        min(memo) as memo
    from memo_affiliates
    where affiliate_fee_bps > 0
    group by tx_id, affiliate
),

-- Where a fee leg exists, its fee is shared among the memo's affiliates by basis points (in practice
-- these memos name one affiliate). Otherwise the fee is estimated as basis points × the input.
memo_era as (
    select
        coalesce(fee_legs.event_id, memo_fees.swap_event_id) as event_id,
        coalesce(fee_legs.block_height, memo_fees.swap_block_height) as block_height,
        coalesce(fee_legs.block_time, memo_fees.swap_block_time) as block_time,
        (coalesce(fee_legs.block_time, memo_fees.swap_block_time) at time zone 'UTC')::date as day,
        memo_fees.tx_id,
        memo_fees.affiliate,
        case when memo_fees.affiliate not like 'thor1%' then memo_fees.affiliate end as thorname,
        case when memo_fees.affiliate like 'thor1%' then memo_fees.affiliate end as affiliate_address,
        memo_fees.affiliate_fee_bps::bigint as affiliate_fee_bps,
        memo_fees.from_asset as asset,
        (memo_fees.from_amount_e8 + coalesce(fee_legs.from_amount_e8, 0))::bigint as gross_amount_e8,
        case
            when fee_legs.event_id is not null
                then floor(fee_legs.from_amount_e8 * memo_fees.affiliate_fee_bps / memo_fees.total_fee_bps)
            else floor(memo_fees.affiliate_fee_bps * memo_fees.from_amount_e8 / 10000)
        end::bigint as fee_amount_e8,
        case
            when fee_legs.event_id is not null
                then floor(fee_legs.to_amount_e8 * memo_fees.affiliate_fee_bps / memo_fees.total_fee_bps)
            else floor(memo_fees.affiliate_fee_bps * memo_fees.input_value_e8 / 10000)
        end::bigint as affiliate_fee_e8,
        case
            when fee_legs.event_id is not null
                then fee_legs.to_amount_usd * memo_fees.affiliate_fee_bps / memo_fees.total_fee_bps
            else memo_fees.affiliate_fee_bps * memo_fees.input_value_usd / 10000
        end as affiliate_fee_usd,
        memo_fees.memo,
        fee_legs.event_id is null as is_estimated
    from memo_fees
    left join fee_legs
        on fee_legs.tx_id = memo_fees.tx_id
),

fees as (
    select * from recorded
    union all
    select * from memo_era
)

select
    event_id,
    block_height,
    block_time,
    day,
    tx_id,
    affiliate,
    thorname,
    affiliate_address,
    affiliate_fee_bps,
    asset,
    {{ units('gross_amount_e8') }} as gross_amount,
    gross_amount_e8,
    {{ units('fee_amount_e8') }} as fee_amount,
    fee_amount_e8,
    {{ units('affiliate_fee_e8') }} as affiliate_fee,
    affiliate_fee_e8,
    affiliate_fee_usd,
    is_estimated,
    memo
from fees
