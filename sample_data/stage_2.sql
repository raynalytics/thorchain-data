-- Sample data, stage 2: blocks 103 and 104 (2026-01-03 and 2026-01-04), loaded after stage 1.
--   SPR the streaming swap begun in stage 1 runs its last two sub-swaps; THORNode's result at block 104
--       shows all four done
--   SFL the other streaming swap from stage 1: its second sub-swap fails at block 103, so there is no new
--       leg, only THORNode's result, and half the deposit is refunded
--   SIP streaming swap ETH -> RUNE, 3 sub-swaps planned, 1 done: still in progress
--   MMM swap BTC -> RUNE, 15 bps to "tr", fee taken from the RUNE output and paid directly
--   No usable RUNE price at block 103 (the last one carries on); bond, node, liquidity and reward events
create temp table t (h bigint, ts bigint);
insert into t values
  (103, (extract(epoch from timestamptz '2026-01-03 18:00:00+00') * 1e9)::bigint),
  (104, (extract(epoch from timestamptz '2026-01-04 06:00:00+00') * 1e9)::bigint);
insert into midgard.block_log (height, timestamp, hash) select h, ts, decode(lpad(h::text, 4, '0'), 'hex') from t;
insert into midgard.rune_price select p, ts from t join (values (103, 0.0), (104, 3.0)) v(h, p) using (h);
insert into midgard.block_pool_depths select pool, a, r, 0, ts from t join (values
  (103, 'BTC.BTC', 200000000, 10000000000000),
  (104, 'BTC.BTC', 200000000, 10000000000000), (104, 'ETH.ETH', 1000000000, 1000000000000)) v(h, pool, a, r) using (h);
insert into midgard.swap_events (tx, chain, from_addr, to_addr, from_asset, from_e8, to_asset, to_e8, memo, pool, to_e8_min, swap_slip_bp, liq_fee_e8, liq_fee_in_rune_e8, _direction, _streaming, _tx_type, streaming_count, streaming_quantity, event_id, block_timestamp)
select tx, chain, 'bc1user', 'bc1vault', fa, fe, ta, te, memo, pool, 0, 10, lf, lfr, dir, streaming, 'swap', scount, sqty, h * 10000000000 + 1000000000 + idx, ts
from t join (values
  (103, 1, 'SPR', 'BTC', 'BTC.BTC', 250000, 'THOR.RUNE', 12400000000, '=:THOR.RUNE:thor1spr:0/1/4', 'BTC.BTC', 100000000, 100000000, 1, true, 3, 4),
  (103, 2, 'MMM', 'BTC', 'BTC.BTC', 1000000, 'THOR.RUNE', 49800000000, '=:THOR.RUNE:thor1m:0:tr:15', 'BTC.BTC', 100000000, 100000000, 1, false, 1, 1),
  (104, 1, 'SPR', 'BTC', 'BTC.BTC', 250000, 'THOR.RUNE', 12400000000, '=:THOR.RUNE:thor1spr:0/1/4', 'BTC.BTC', 100000000, 100000000, 1, true, 4, 4),
  (104, 2, 'SIP', 'ETH', 'ETH.ETH', 10000000, 'THOR.RUNE', 9900000000, '=:THOR.RUNE:thor1sip:0/1/3', 'ETH.ETH', 100000000, 100000000, 1, true, 1, 3)
) v(h, idx, tx, chain, fa, fe, ta, te, memo, pool, lf, lfr, dir, streaming, scount, sqty) using (h);
insert into midgard.affiliate_fee_events (tx_id, fee_amt, gross_amt, fee_bps, memo, asset, rune_address, thorname, _fee_amt_in_rune, event_id, block_timestamp)
select 'MMM', 74700000, 49800000000, 15, '=:THOR.RUNE:thor1m:0:tr:15', 'THOR.RUNE', 'thor1aff', 'tr', 74700000, 103 * 10000000000 + 1000000000 + 3, ts from t where h = 103;
insert into midgard.streaming_swap_details_events (tx_id, interval, quantity, count, last_height, deposit_asset, deposit_e8, in_asset, in_e8, out_asset, out_e8, failed_swaps, failed_swap_reasons, event_id, block_timestamp)
select 'SFL', 1, 2, 2, 103, 'BTC.BTC', 200000, 'BTC.BTC', 100000, 'THOR.RUNE', 4900000000, '{2}'::bigint[], '{"emit asset less than price limit"}'::text[], 103 * 10000000000 + 9000000000 + 1, ts
from t where h = 103
union all
select 'SPR', 1, 4, 4, 104, 'BTC.BTC', 1000000, 'BTC.BTC', 1000000, 'THOR.RUNE', 49600000000, '{}'::bigint[], '{}'::text[], 104 * 10000000000 + 9000000000 + 1, ts
from t where h = 104;
insert into midgard.stake_events (pool, asset_tx, asset_chain, asset_addr, asset_e8, stake_units, rune_tx, rune_addr, rune_e8, _asset_in_rune_e8, memo, event_id, block_timestamp)
select 'ETH.ETH', 'ADD2', 'ETH', '0xlp', 100000000, 1000000000, 'ADD2R', 'thor1lp2', 10000000000, 10000000000, '+:ETH.ETH', 104 * 10000000000 + 1000000000 + 5, ts from t where h = 104;
insert into midgard.rewards_events select 100000000, h * 10000000000 + 9000000000, ts from t;
insert into midgard.rewards_event_entries select 'BTC.BTC', 50000000, 0, h * 10000000000 + 9000000000, ts from t;
insert into midgard.update_node_account_status_events select 'thor1n2', 'Standby', 'Active', 104 * 10000000000 + 9000000000 + 5, ts from t where h = 104;
insert into midgard.bond_events (tx, asset_e8, bond_type, e8, node_addr, event_id, block_timestamp)
select 'BOND2', 0, 'bond_paid', 100000000000, 'thor1n2', 104 * 10000000000 + 1000000000 + 6, ts from t where h = 104;
insert into midgard.pool_events (asset, status, event_id, block_timestamp)
select 'BTC.BTC', 'Suspended', 103 * 10000000000 + 9000000000 + 20, ts from t where h = 103;
insert into midgard_agg.members_count (pool, count, block_timestamp)
select 'ETH.ETH', 1, ts from t where h = 104;
