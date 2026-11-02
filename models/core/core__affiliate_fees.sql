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

estimated as (
    select
        event_id,
        block_height,
        block_time,
        (block_time at time zone 'UTC')::date as day,
        tx_id,
        affiliate,
        case when affiliate not like 'thor1%' then affiliate end as thorname,
        case when affiliate like 'thor1%' then affiliate end as affiliate_address,
        sum(affiliate_fee_bps)::bigint as affiliate_fee_bps,
        from_asset as asset,
        from_amount_e8::bigint as gross_amount_e8,
        floor(sum(affiliate_fee_bps) * from_amount_e8 / 10000)::bigint as fee_amount_e8,
        floor(sum(affiliate_fee_bps) * input_value_e8 / 10000)::bigint as affiliate_fee_e8,
        sum(affiliate_fee_bps) * input_value_usd / 10000 as affiliate_fee_usd,
        memo,
        true as is_estimated
    from memo_affiliates
    where affiliate_fee_bps > 0
    group by event_id, block_height, block_time, tx_id, affiliate, from_asset, from_amount_e8,
        input_value_e8, input_value_usd, memo
),

fees as (
    select * from recorded
    union all
    select * from estimated
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
