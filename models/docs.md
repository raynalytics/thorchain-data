{% docs __overview__ %}
# THORChain data models

Clean tables built from Midgard's index of THORChain.

| Schema | Holds |
| --- | --- |
| `events` | One table per THORChain event type, renamed and typed, otherwise as recorded on chain. |
| `core` | Main tables that combine events: swaps, liquidity, fees, earnings, prices, nodes. |
| `daily` | Daily summaries for the network, each pool and each affiliate. |
| `legacy` | Retired features: loans and Yggdrasil vaults. |

Conventions used in every table:

- `block_time` is a UTC timestamp and `day` a UTC date.
- Amounts appear twice: `<name>` in real units (1.5 = 1.5 RUNE or 1.5 of the asset) and `<name>_e8` as the raw chain integer (150000000).
- `<name>_usd` values are priced at the block the event happened in: RUNE from Midgard's per-block RUNE price, other assets from their pool's depths at that block times the RUNE price.
- Swap volume comes in two measures: `swap_volume_usd` counts every pool leg (a swap routed through RUNE counts twice), including legs that convert affiliate fees and internal swaps made by the protocol; `user_volume_usd` counts each user swap once at its full input value, before any affiliate fee (Midgard's measure).
- Swap legs are of three types (`core.swap_legs.leg_type`): `user` legs make up the user's swap; `affiliate_fee` legs swap an affiliate fee to RUNE inside the user's transaction; `internal` legs are swaps the protocol makes on its own account.
{% enddocs %}

{% docs event_id %}
Midgard's identifier for the event: block height × 10¹⁰ plus the event's position in the block. Orders events within the chain.
{% enddocs %}

{% docs block_height %}
THORChain block height.
{% enddocs %}

{% docs block_time %}
Time of the block, UTC.
{% enddocs %}

{% docs day %}
UTC date.
{% enddocs %}

{% docs tx_id %}
Hash of the transaction, as recorded on its chain (the inbound chain for user transactions).
{% enddocs %}

{% docs chain %}
Chain the transaction came in on, e.g. `BTC`, `ETH`, `THOR`.
{% enddocs %}

{% docs from_address %}
Address that sent the transaction.
{% enddocs %}

{% docs to_address %}
Address the transaction was sent to.
{% enddocs %}

{% docs pool %}
Pool, named by its asset, e.g. `BTC.BTC`.
{% enddocs %}

{% docs asset %}
Asset in THORChain notation (`CHAIN.SYMBOL`, `CHAIN/SYMBOL` for synths, `CHAIN~SYMBOL` for trade assets, `CHAIN-SYMBOL` for secured assets).
{% enddocs %}

{% docs amount %}
Amount of `asset`, in real units.
{% enddocs %}

{% docs amount_e8 %}
Amount of `asset`, raw chain integer (1e-8 units).
{% enddocs %}

{% docs memo %}
Transaction memo.
{% enddocs %}

{% docs tx_type %}
Transaction type Midgard reads from the memo, e.g. `swap`, `add`, `withdraw`, `bond`, `unknown`.
{% enddocs %}

{% docs rune_address %}
THORChain (`thor1…`) address.
{% enddocs %}

{% docs asset_address %}
Address on the asset's own chain.
{% enddocs %}

{% docs node_address %}
Node operator's THORChain address.
{% enddocs %}

{% docs affiliate %}
Affiliate: its THORName where it has one, otherwise its THORChain address.
{% enddocs %}

{% docs rune_price_usd %}
Price of 1 RUNE in USD at the block (end of day in daily tables): Midgard's median over the pools THORChain uses as USD price anchors. Blocks where no anchor pool was usable take the last recorded price.
{% enddocs %}

{% docs asset_price %}
Price of 1 unit of the pool's asset in RUNE: RUNE depth ÷ asset depth.
{% enddocs %}

{% docs asset_price_usd %}
Price of 1 unit of the pool's asset in USD: `asset_price` × RUNE price.
{% enddocs %}

{% docs swap_volume %}
Swap volume in RUNE, every pool leg counted, affiliate fee and internal legs included: the RUNE side of each leg (for legs paying out RUNE, the RUNE paid out plus the liquidity fee). Same measure as Midgard's swap volume.
{% enddocs %}

{% docs swap_volume_usd %}
`swap_volume` in USD at each leg's block. Default volume measure.
{% enddocs %}

{% docs user_volume_usd %}
Full value of the swap's input in USD, before any affiliate fee, at the block of each input leg; each user swap counted once. Before affiliate fee events exist, the fee was skimmed from the input and swapped to RUNE in its own leg, so that leg's input is included. Matches the input Midgard reports for a swap.
{% enddocs %}

{% docs liquidity_fee %}
Liquidity fee charged by the pools on swaps, in RUNE (the total for the row: one leg, one swap, one block or one day).
{% enddocs %}

{% docs pool_rewards %}
Block rewards paid to liquidity pools, in RUNE. Can be negative for a pool when rewards are redistributed away from it.
{% enddocs %}

{% docs bond_rewards %}
Block rewards paid to bonded nodes, in RUNE.
{% enddocs %}

{% docs block_rewards %}
Block rewards paid out, in RUNE: `pool_rewards` + `bond_rewards`.
{% enddocs %}

{% docs liquidity_earnings %}
Earnings of liquidity providers, in RUNE: `liquidity_fee` + `pool_rewards`.
{% enddocs %}

{% docs earnings %}
Total protocol earnings, in RUNE: `liquidity_fee` + `block_rewards`.
{% enddocs %}

{% docs total_value_pooled %}
Value held in pools, in RUNE: twice the RUNE depth, since each pool holds equal value of RUNE and asset.
{% enddocs %}

{% docs total_value_bonded %}
RUNE bonded by nodes: the running total of bond changes (bonds paid and rewards added, bonds returned and costs subtracted).
{% enddocs %}

{% docs total_value_locked %}
`total_value_pooled` + `total_value_bonded`, in RUNE.
{% enddocs %}

{% docs liquidity_units %}
Liquidity provider units of the pool.
{% enddocs %}

{% docs vault_pubkey %}
Public key of the THORChain vault.
{% enddocs %}
