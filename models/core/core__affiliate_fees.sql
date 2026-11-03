{{ config(
    materialized='incremental',
    unique_key='tx_id',
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['tx_id']}, {'columns': ['block_height']}, {'columns': ['day']}]
) }}

{%- if is_incremental() %}
{%- set last_block = high_water_block() %}
{%- endif %}

-- An incremental run rebuilds the fees of every transaction with swap legs or affiliate fee events
-- since the last block in the table.
with
{%- if is_incremental() %}
touched_transactions as (
    select tx_id from {{ ref('core__swap_legs') }}
    where block_height > {{ last_block }} and leg_type <> 'internal'
    union
    select tx_id from {{ source('midgard', 'affiliate_fee_events') }}
    where block_timestamp > {{ block_timestamp_ns(last_block) }}
),

swap_legs as (
    select * from {{ ref('core__swap_legs') }}
    where tx_id in (select tx_id from touched_transactions)
),
{%- else %}
swap_legs as (
    select * from {{ ref('core__swap_legs') }}
),
{%- endif %}

first_fee_event as (
    select coalesce(
        (
            select event_id
            from {{ source('midgard', 'affiliate_fee_events') }}
            order by block_timestamp, event_id
            limit 1
        ),
        9223372036854775807
    ) as event_id
),

recorded as (
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
    {%- if is_incremental() %}
    where fees.tx_id in (select tx_id from touched_transactions)
    {%- endif %}
),

-- User swaps that started before affiliate fee events exist, with their input amount and value.
swap_inputs as (
    select
        legs.tx_id,
        min(legs.event_id) as event_id,
        min(legs.block_height) as block_height,
        min(legs.block_time) as block_time,
        firsts.from_asset,
        firsts.from_address,
        firsts.to_address,
        firsts.memo,
        bool_or(legs.is_streaming) as is_streaming,
        sum(legs.from_amount_e8) filter (where legs.from_asset = firsts.from_asset) as from_amount_e8,
        sum(legs.swap_volume_e8) filter (where legs.from_asset = firsts.from_asset) as input_value_e8,
        sum(legs.from_amount_usd) filter (where legs.from_asset = firsts.from_asset) as input_value_usd
    from swap_legs as legs
    inner join (
        select distinct on (tx_id)
            tx_id,
            event_id,
            from_asset,
            from_address,
            to_address,
            memo
        from swap_legs
        where leg_type = 'user'
        order by tx_id, event_id
    ) as firsts
        on firsts.tx_id = legs.tx_id
    where legs.leg_type = 'user'
        and firsts.event_id < (select event_id from first_fee_event)
        and not exists (select 1 from recorded where recorded.tx_id = legs.tx_id)
    group by legs.tx_id, firsts.from_asset, firsts.from_address, firsts.to_address, firsts.memo
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
        min(from_address) as from_address,
        min(to_address) as to_address,
        bool_or(is_streaming) as is_streaming,
        min(from_amount_e8) as from_amount_e8,
        min(input_value_e8) as input_value_e8,
        min(input_value_usd) as input_value_usd,
        min(memo) as memo
    from memo_affiliates
    where affiliate_fee_bps > 0
        and from_asset not like '%~%'
    group by tx_id, affiliate
),

-- Before affiliate fee events exist, THORChain took the fee from the input before swapping, so the
-- full input is the user legs plus the fee:
-- - for inputs from other chains, the fee was swapped to RUNE in a leg of its own (one per transaction);
--   the RUNE that leg produced is the fee paid.
-- - for RUNE and synths deposited on THORChain, the fee was sent straight from the Asgard module to the
--   affiliate, in the input asset, in the deposit's own transaction. The deposit is the user's transfer
--   of the full input to Asgard (in the swap's first block, or a few blocks earlier when the swap queue
--   was full) whose amount less floor(basis points × amount / 10000) is the swapped input; the payment
--   is Asgard's transfer of at most that fee in the same transaction (early versions also deducted the
--   network fee from it). The fee taken is the formula's amount; the fee paid is the transfer.
-- - for trade assets, THORNode tried the same bank transfer, which fails because trade assets are not
--   bank coins, and the swap withdrew only the reduced amount from the trade account: no fee was taken
--   or paid, so these swaps get no fee row.
fee_legs as (
    select
        legs.tx_id,
        legs.event_id,
        legs.block_height,
        legs.block_time,
        swaps.from_amount_e8 + legs.from_amount_e8 as gross_amount_e8,
        legs.from_amount_e8 as fee_amount_e8,
        legs.to_amount_e8 as affiliate_fee_e8,
        legs.to_amount_usd as affiliate_fee_usd
    from swap_legs as legs
    inner join swap_inputs as swaps
        on swaps.tx_id = legs.tx_id
    where legs.leg_type = 'affiliate_fee'
),

native_swaps as (
    select distinct on (tx_id)
        tx_id,
        from_asset,
        from_address,
        to_address,
        swap_block_height,
        is_streaming,
        from_amount_e8,
        total_fee_bps
    from memo_fees
    where from_asset = 'THOR.RUNE' or from_asset like '%/%'
    order by tx_id
),

-- Transfers in the blocks where those deposits can be: from 10 blocks before the first such swap to
-- the last one.
transfers as (
    {{ events__transfers_sql(midgard_rows(
        'transfer_events',
        'block_timestamp between (select coalesce(min(timestamp), 0) from ' ~ source('midgard', 'block_log')
            ~ ' where height >= (select min(swap_block_height) - 10 from native_swaps))'
            ~ ' and (select coalesce(max(timestamp), -1) from ' ~ source('midgard', 'block_log')
            ~ ' where height <= (select max(swap_block_height) from native_swaps))'
    )) }}
),

native_deposits as (
    select distinct on (swaps.tx_id)
        swaps.tx_id,
        swaps.from_asset,
        deposits.event_id,
        deposits.block_height,
        deposits.amount_e8 as gross_amount_e8,
        floor(deposits.amount_e8 * swaps.total_fee_bps / 10000) as fee_due_e8
    from native_swaps as swaps
    inner join transfers as deposits
        on deposits.from_address = swaps.from_address
        and deposits.to_address = swaps.to_address
        and deposits.asset = swaps.from_asset
        and deposits.block_height between swaps.swap_block_height - 10 and swaps.swap_block_height
    where case
        when swaps.is_streaming
            then deposits.amount_e8 - floor(deposits.amount_e8 * swaps.total_fee_bps / 10000) >= swaps.from_amount_e8 - 1
        else abs(deposits.amount_e8 - floor(deposits.amount_e8 * swaps.total_fee_bps / 10000) - swaps.from_amount_e8) <= 1
    end
    order by swaps.tx_id, deposits.event_id desc
),

native_payments as (
    select distinct on (deposits.tx_id)
        deposits.tx_id,
        payments.event_id,
        payments.block_height,
        payments.block_time,
        deposits.gross_amount_e8,
        deposits.fee_due_e8 as fee_amount_e8,
        payments.amount_e8 as affiliate_fee_e8,
        payments.amount * prices.rune_price_usd as affiliate_fee_usd
    from native_deposits as deposits
    inner join native_swaps as swaps
        on swaps.tx_id = deposits.tx_id
    inner join transfers as payments
        on payments.block_height = deposits.block_height
        and payments.event_id / 10000 = deposits.event_id / 10000
        and payments.from_address = swaps.to_address
        and payments.asset = deposits.from_asset
        and payments.amount_e8 between 1 and deposits.fee_due_e8 + 1
    left join {{ ref('core__rune_price') }} as prices
        on prices.block_height = payments.block_height
    order by deposits.tx_id, payments.amount_e8 desc
),

-- Synth payments are valued in RUNE at their pool's price in the block.
native_payment_pools as (
    select
        payments.*,
        case when swaps.from_asset like '%/%' then replace(swaps.from_asset, '/', '.') end as pool
    from native_payments as payments
    inner join native_swaps as swaps
        on swaps.tx_id = payments.tx_id
),

native_payment_prices as {{ asset_prices_as_of('native_payment_pools') }},

native_payments_valued as (
    select
        tx_id,
        event_id,
        block_height,
        block_time,
        gross_amount_e8,
        fee_amount_e8,
        floor(affiliate_fee_e8 * rune_per_unit)::bigint as affiliate_fee_e8,
        affiliate_fee_usd * rune_per_unit as affiliate_fee_usd
    from (
        select
            payments.*,
            case when payments.pool is null then 1 else prices.asset_price end as rune_per_unit
        from native_payment_pools as payments
        left join native_payment_prices as prices
            on prices.pool = payments.pool
            and prices.block_height = payments.block_height
    ) as priced
),

fees_paid as (
    select * from fee_legs
    union all
    select * from native_payments_valued
),

-- A fee paid is shared among the memo's affiliates by basis points (in practice these memos name one
-- affiliate). Where none was found, the fee is estimated as basis points × the input.
memo_era as (
    select
        coalesce(paid.event_id, memo_fees.swap_event_id) as event_id,
        coalesce(paid.block_height, memo_fees.swap_block_height) as block_height,
        coalesce(paid.block_time, memo_fees.swap_block_time) as block_time,
        (coalesce(paid.block_time, memo_fees.swap_block_time) at time zone 'UTC')::date as day,
        memo_fees.tx_id,
        memo_fees.affiliate,
        case when memo_fees.affiliate not like 'thor1%' then memo_fees.affiliate end as thorname,
        case when memo_fees.affiliate like 'thor1%' then memo_fees.affiliate end as affiliate_address,
        memo_fees.affiliate_fee_bps::bigint as affiliate_fee_bps,
        memo_fees.from_asset as asset,
        coalesce(paid.gross_amount_e8, memo_fees.from_amount_e8)::bigint as gross_amount_e8,
        case
            when paid.event_id is not null
                then floor(paid.fee_amount_e8 * memo_fees.affiliate_fee_bps / memo_fees.total_fee_bps)
            else floor(memo_fees.affiliate_fee_bps * memo_fees.from_amount_e8 / 10000)
        end::bigint as fee_amount_e8,
        case
            when paid.event_id is not null
                then floor(paid.affiliate_fee_e8 * memo_fees.affiliate_fee_bps / memo_fees.total_fee_bps)
            else floor(memo_fees.affiliate_fee_bps * memo_fees.input_value_e8 / 10000)
        end::bigint as affiliate_fee_e8,
        case
            when paid.event_id is not null
                then paid.affiliate_fee_usd * memo_fees.affiliate_fee_bps / memo_fees.total_fee_bps
            else memo_fees.affiliate_fee_bps * memo_fees.input_value_usd / 10000
        end as affiliate_fee_usd,
        memo_fees.memo,
        paid.event_id is null as is_estimated
    from memo_fees
    left join fees_paid as paid
        on paid.tx_id = memo_fees.tx_id
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
