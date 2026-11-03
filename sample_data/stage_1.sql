-- Sample data, stage 1: blocks 96 to 102 (2025-12-31 to 2026-01-03), loaded into an empty Midgard
-- database. Used by scripts/check_incremental.sh; sample_data/stage_2.sql adds later blocks.
create temp table t (h bigint, ts bigint);
insert into t values
  (96,  (extract(epoch from timestamptz '2025-12-31 10:00:00+00') * 1e9)::bigint),
  (97,  (extract(epoch from timestamptz '2025-12-31 11:00:00+00') * 1e9)::bigint),
  (100, (extract(epoch from timestamptz '2026-01-01 23:00:00+00') * 1e9)::bigint),
  (101, (extract(epoch from timestamptz '2026-01-02 01:00:00+00') * 1e9)::bigint),
  (102, (extract(epoch from timestamptz '2026-01-03 12:00:00+00') * 1e9)::bigint);
insert into midgard.block_log (height, timestamp, hash) select h, ts, decode(lpad(h::text, 4, '0'), 'hex') from t;
insert into midgard.rune_price select p, ts from t join (values (96, 2.0), (97, 2.0), (100, 2.0), (101, 2.5), (102, 0.0)) v(h, p) using (h);
insert into midgard.block_pool_depths select pool, a, r, 0, ts from t join (values
  (96, 'BTC.BTC', 100000000, 5000000000000), (96, 'ETH.ETH', 1000000000, 1000000000000),
  (100, 'BTC.BTC', 100000000, 5000000000000), (100, 'ETH.ETH', 1000000000, 1000000000000),
  (102, 'BTC.BTC', 200000000, 10000000000000)) v(h, pool, a, r) using (h);
-- Before affiliate fee events (blocks 96-97):
--   CCC double swap BTC -> RUNE -> ETH, 30 bps to "tr": fee leg sells floor(30 x 10,000,000 / 10000) = 30,000 sats
--   DDD swap BTC -> RUNE, 50 bps to "tr": fee leg sells 10,000 of 2,000,000 sats, both legs BTC -> RUNE
--   EEE streaming swap BTC -> RUNE -> ETH, 3 sub-swaps planned, 2 executed, 20 bps: fee leg is the single
--       non-streaming leg; THORNode's result (block 97) shows the third failed and its share was refunded
--   GGG swap RUNE -> BTC, 15 bps to "tr": the fee is sent to the affiliate by transfer in the deposit's
--       transaction: deposit 20030045067, fee floor(15 x 20030045067 / 10000) = 30045067, swapped 20000000000
--   JJJ swap RUNE -> BTC, 10 bps to thor1j, deposited a block before the swap ran: deposit 10010010010,
--       fee 10010010, paid less the 0.02 RUNE network fee (early versions) = 8010010; an unrelated Asgard
--       transfer in another transaction of the same block must not match
--   KKK swap RUNE -> BTC, 20 bps to "tr", no payment recorded: the fee is estimated (0.1 RUNE) and added
--       to the input
--   SSS swap synth BTC/BTC -> RUNE, 20 bps to thor1s: deposit 1000000, fee 2000 paid in BTC/BTC by transfer
--       (= 1 RUNE at 50000 RUNE per BTC), swapped 998000
--   SSE swap synth ETH/ETH -> RUNE, 10 bps to "tr", no payment recorded: the fee is estimated
--       (10000 ETH/ETH, 0.1 RUNE) and added to the input
--   TTT swap trade asset BTC~BTC -> RUNE, 30 bps to "tr": THORNode's fee transfer fails for trade assets,
--       so no fee is taken and the input is what the swap withdrew
--   HHH swap BTC -> RUNE, 20 bps to "tr", no fee leg recorded: the fee is estimated
-- After (blocks 101-102):
--   AAA double swap BTC -> RUNE -> ETH, 10 bps to "tr": fee taken from the ETH output, sold in an ETH -> RUNE leg
--   BBB single swap RUNE -> BTC
--   internal swaps: all-zero tx id, empty tx id, preferred-asset payout
--   SPR streaming swap BTC -> RUNE, 4 sub-swaps planned, 2 done by block 102: still in progress
--       (sample_data/stage_2.sql finishes it)
--   SFL streaming swap BTC -> RUNE, 2 sub-swaps planned, 1 done by block 102: still in progress (its second
--       sub-swap fails in stage 2)
insert into midgard.swap_events (tx, chain, from_addr, to_addr, from_asset, from_e8, to_asset, to_e8, memo, pool, to_e8_min, swap_slip_bp, liq_fee_e8, liq_fee_in_rune_e8, _direction, _streaming, _tx_type, streaming_count, streaming_quantity, event_id, block_timestamp)
select tx, chain, 'bc1user', 'bc1vault', fa, fe, ta, te, memo, pool, 0, 10, lf, lfr, dir, streaming, 'swap', scount, sqty, h * 10000000000 + 1000000000 + idx, ts
from t join (values
  (96, 1, 'CCC', 'BTC', 'BTC.BTC', 9970000, 'THOR.RUNE', 498000000000, '=:ETH.ETH:0xc:0:tr:30', 'BTC.BTC', 500000000, 500000000, 1, false, 1, 1),
  (96, 2, 'CCC', 'BTC', 'THOR.RUNE', 498000000000, 'ETH.ETH', 497000000, '=:ETH.ETH:0xc:0:tr:30', 'ETH.ETH', 300000, 300000000, 0, false, 1, 1),
  (96, 3, 'CCC', 'BTC', 'BTC.BTC', 30000, 'THOR.RUNE', 1490000000, '=:ETH.ETH:0xc:0:tr:30', 'BTC.BTC', 10000000, 10000000, 1, false, 1, 1),
  (96, 4, 'DDD', 'BTC', 'BTC.BTC', 1990000, 'THOR.RUNE', 99400000000, '=:THOR.RUNE:thor1d:0:tr:50', 'BTC.BTC', 100000000, 100000000, 1, false, 1, 1),
  (96, 5, 'DDD', 'BTC', 'BTC.BTC', 10000, 'THOR.RUNE', 499000000, '=:THOR.RUNE:thor1d:0:tr:50', 'BTC.BTC', 1000000, 1000000, 1, false, 1, 1),
  (96, 6, 'EEE', 'BTC', 'BTC.BTC', 998000, 'THOR.RUNE', 49800000000, '=:ETH.ETH:0xe:0/1/3:tr:20', 'BTC.BTC', 100000000, 100000000, 1, true, 1, 3),
  (96, 7, 'EEE', 'BTC', 'THOR.RUNE', 49800000000, 'ETH.ETH', 49700000, '=:ETH.ETH:0xe:0/1/3:tr:20', 'ETH.ETH', 100000, 100000000, 0, true, 1, 3),
  (96, 8, 'EEE', 'BTC', 'BTC.BTC', 6000, 'THOR.RUNE', 299000000, '=:ETH.ETH:0xe:0/1/3:tr:20', 'BTC.BTC', 1000000, 1000000, 1, true, 1, 1),
  (97, 1, 'EEE', 'BTC', 'BTC.BTC', 998000, 'THOR.RUNE', 49800000000, '=:ETH.ETH:0xe:0/1/3:tr:20', 'BTC.BTC', 100000000, 100000000, 1, true, 2, 3),
  (97, 2, 'EEE', 'BTC', 'THOR.RUNE', 49800000000, 'ETH.ETH', 49700000, '=:ETH.ETH:0xe:0/1/3:tr:20', 'ETH.ETH', 100000, 100000000, 0, true, 2, 3),
  (96, 11, 'SSS', 'THOR', 'BTC/BTC', 998000, 'THOR.RUNE', 49800000000, '=:THOR.RUNE:thor1dest:0:thor1s:20', 'BTC.BTC', 100000000, 100000000, 1, false, 1, 1),
  (96, 12, 'SSE', 'THOR', 'ETH/ETH', 10000000, 'THOR.RUNE', 9900000000, '=:THOR.RUNE:thor1dest:0:tr:10', 'ETH.ETH', 100000000, 100000000, 1, false, 1, 1),
  (96, 13, 'TTT', 'THOR', 'BTC~BTC', 500000, 'THOR.RUNE', 24900000000, '=:THOR.RUNE:thor1dest:0:tr:30', 'BTC.BTC', 100000000, 100000000, 1, false, 1, 1),
  (97, 4, 'JJJ', 'THOR', 'THOR.RUNE', 10000000000, 'BTC.BTC', 198000, '=:BTC.BTC:bc1j:0:thor1j:10', 'BTC.BTC', 1000, 50000000, 0, false, 1, 1),
  (97, 3, 'HHH', 'BTC', 'BTC.BTC', 500000, 'THOR.RUNE', 24900000000, '=:THOR.RUNE:thor1h:0:tr:20', 'BTC.BTC', 100000000, 100000000, 1, false, 1, 1),
  (100, 2, 'KKK', 'THOR', 'THOR.RUNE', 5000000000, 'BTC.BTC', 98000, '=:BTC.BTC:bc1k:0:tr:20', 'BTC.BTC', 500, 25000000, 0, false, 1, 1),
  (100, 1, 'GGG', 'THOR', 'THOR.RUNE', 20000000000, 'BTC.BTC', 398000, '=:BTC.BTC:bc1g:0:tr:15', 'BTC.BTC', 2000, 100000000, 0, false, 1, 1),
  (101, 1, 'AAA', 'BTC', 'BTC.BTC', 10000000, 'THOR.RUNE', 490000000000, '=:ETH.ETH:0xdest:0/1/0:tr:10', 'BTC.BTC', 10000000000, 10000000000, 1, false, 1, 1),
  (101, 2, 'AAA', 'BTC', 'THOR.RUNE', 490000000000, 'ETH.ETH', 480000000, '=:ETH.ETH:0xdest:0/1/0:tr:10', 'ETH.ETH', 2000000, 2000000000, 0, false, 1, 1),
  (101, 4, 'AAA', 'BTC', 'ETH.ETH', 480000, 'THOR.RUNE', 470000000, '=:THOR.RUNE:thor1aff:0:tr:0', 'ETH.ETH', 5000000, 5000000, 1, false, 1, 1),
  (101, 5, 'SPR', 'BTC', 'BTC.BTC', 250000, 'THOR.RUNE', 12400000000, '=:THOR.RUNE:thor1spr:0/1/4', 'BTC.BTC', 100000000, 100000000, 1, true, 1, 4),
  (102, 6, 'SPR', 'BTC', 'BTC.BTC', 250000, 'THOR.RUNE', 12400000000, '=:THOR.RUNE:thor1spr:0/1/4', 'BTC.BTC', 100000000, 100000000, 1, true, 2, 4),
  (102, 7, 'SFL', 'BTC', 'BTC.BTC', 100000, 'THOR.RUNE', 4900000000, '=:THOR.RUNE:thor1sfl:0/1/2', 'BTC.BTC', 100000000, 100000000, 1, true, 1, 2),
  (102, 1, 'BBB', 'THOR', 'THOR.RUNE', 100000000000, 'BTC.BTC', 1900000, 'SWAP:BTC.BTC:bc1dest', 'BTC.BTC', 20000, 1000000000, 0, false, 1, 1),
  (102, 3, '0000000000000000000000000000000000000000000000000000000000000000', 'THOR', 'THOR.RUNE', 10000000000, 'BTC.BTC', 190000, '', 'BTC.BTC', 2000, 100000000, 0, false, 1, 1),
  (102, 4, '', 'THOR', 'BTC.BTC', 100000, 'THOR.RUNE', 4900000000, '', 'BTC.BTC', 100000000, 100000000, 1, false, 1, 1),
  (102, 5, 'PA1', 'THOR', 'THOR.RUNE', 5000000000, 'ETH.ETH', 4900000, 'THOR-PREFERRED-ASSET-tr', 'ETH.ETH', 100000, 100000000, 0, false, 1, 1)
) v(h, idx, tx, chain, fa, fe, ta, te, memo, pool, lf, lfr, dir, streaming, scount, sqty) using (h);
insert into midgard.streaming_swap_details_events (tx_id, interval, quantity, count, last_height, deposit_asset, deposit_e8, in_asset, in_e8, out_asset, out_e8, failed_swaps, failed_swap_reasons, event_id, block_timestamp)
select 'EEE', 1, 3, 3, 97, 'BTC.BTC', 2994000, 'BTC.BTC', 1996000, 'ETH.ETH', 99400000, '{3}', '{"emit asset less than price limit"}', 97 * 10000000000 + 9000000000 + 1, ts
from t where h = 97;
insert into midgard.transfer_events (from_addr, to_addr, asset, amount_e8, event_id, block_timestamp)
select f, tt, asset, a, h * 10000000000 + 1000000000 + txi * 10000 + ei, ts
from t join (values
  (100, 5, 0, 'bc1user', 'thor1reserve', 'THOR.RUNE', 2000000),
  (100, 5, 1, 'bc1user', 'bc1vault', 'THOR.RUNE', 20030045067),
  (100, 5, 2, 'bc1vault', 'thor1tr', 'THOR.RUNE', 30045067),
  (96, 6, 0, 'bc1user', 'thor1reserve', 'THOR.RUNE', 2000000),
  (96, 6, 1, 'bc1user', 'bc1vault', 'THOR.RUNE', 10010010010),
  (96, 6, 2, 'bc1vault', 'thor1j', 'THOR.RUNE', 8010010),
  (96, 7, 0, 'bc1vault', 'thor1other', 'THOR.RUNE', 5000000),
  (96, 8, 0, 'bc1user', 'thor1reserve', 'THOR.RUNE', 2000000),
  (96, 8, 1, 'bc1user', 'bc1vault', 'BTC/BTC', 1000000),
  (96, 8, 2, 'bc1vault', 'thor1s', 'BTC/BTC', 2000)
) v(h, txi, ei, f, tt, asset, a) using (h);
insert into midgard.affiliate_fee_events (tx_id, fee_amt, gross_amt, fee_bps, memo, asset, rune_address, thorname, _fee_amt_in_rune, event_id, block_timestamp)
select 'AAA', 480000, 480000000, 10, '=:ETH.ETH:0xdest:0/1/0:tr:10', 'ETH.ETH', 'thor1aff', 'tr', 480000000, 101 * 10000000000 + 1000000000 + 3, ts from t where h = 101;
insert into midgard.stake_events (pool, asset_tx, asset_chain, asset_addr, asset_e8, stake_units, rune_tx, rune_addr, rune_e8, _asset_in_rune_e8, memo, event_id, block_timestamp)
select 'BTC.BTC', 'ADD1', 'BTC', 'bc1lp', 100000000, 10000000000, 'ADD1R', 'thor1lp', 5000000000000, 5000000000000, '+:BTC.BTC', 96 * 10000000000 + 1000000000 + 9, ts from t where h = 96;
insert into midgard.withdraw_events (tx, chain, from_addr, to_addr, asset, asset_e8, emit_asset_e8, emit_rune_e8, memo, pool, stake_units, basis_points, asymmetry, imp_loss_protection_e8, _emit_asset_in_rune_e8, _tx_type, event_id, block_timestamp)
select 'WD1', 'THOR', 'thor1lp', 'thor1vault', 'THOR.RUNE', 0, 25000000, 1250000000000, '-:BTC.BTC:2500', 'BTC.BTC', 2500000000, 2500, 0, 0, 1250000000000, 'withdraw', 102 * 10000000000 + 1000000000 + 2, ts from t where h = 102;
insert into midgard.rewards_events select 100000000, h * 10000000000 + 9000000000, ts from t;
insert into midgard.rewards_event_entries select 'BTC.BTC', 50000000, 0, h * 10000000000 + 9000000000, ts from t;
insert into midgard.update_node_account_status_events select n, 'Ready', 'Active', 96 * 10000000000 + 9000000000 + i, ts from t, (values ('thor1n1', 1), ('thor1n2', 2)) v(n, i) where h = 96;
insert into midgard.update_node_account_status_events select 'thor1n2', 'Active', 'Standby', 102 * 10000000000 + 9000000000 + 5, ts from t where h = 102;
insert into midgard.bond_events (tx, asset_e8, bond_type, e8, node_addr, event_id, block_timestamp)
select 'BOND1', 0, 'bond_paid', 300000000000000, 'thor1n1', 96 * 10000000000 + 1000000000 + 10, ts from t where h = 96;
insert into midgard.pool_events (asset, status, event_id, block_timestamp)
select pool, status, h * 10000000000 + 9000000000 + 20 + i, ts from t join (values
  (96, 'BTC.BTC', 'Available', 1), (96, 'ETH.ETH', 'Staged', 2), (100, 'ETH.ETH', 'Available', 1)) v(h, pool, status, i) using (h);
insert into midgard_agg.members_count (pool, count, block_timestamp)
select pool, n, ts from t join (values (96, 'BTC.BTC', 1), (102, 'BTC.BTC', 2)) v(h, pool, n) using (h);
