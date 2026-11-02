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
    {{ units('fees.gross_amt') }} as gross_amount,
    fees.gross_amt as gross_amount_e8,
    {{ units('fees.fee_amt') }} as fee_amount,
    fees.fee_amt as fee_amount_e8,
    {{ units('fees._fee_amt_in_rune') }} as affiliate_fee,
    fees._fee_amt_in_rune as affiliate_fee_e8,
    {{ units('fees._fee_amt_in_rune') }} * prices.rune_price_usd as affiliate_fee_usd,
    fees.memo
from {{ source('midgard', 'affiliate_fee_events') }} as fees
left join {{ ref('core__rune_price') }} as prices
    on prices.block_height = {{ block_height('fees.event_id') }}
