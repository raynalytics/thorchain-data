{{ config(indexes=[{'columns': ['pool', 'block_height'], 'unique': true}]) }}

select
    blocks.height as block_height,
    {{ block_time('blocks.timestamp') }} as block_time,
    {{ block_day('blocks.timestamp') }} as day,
    depths.pool,
    {{ units('depths.asset_e8') }} as asset_depth,
    depths.asset_e8 as asset_depth_e8,
    {{ units('depths.rune_e8') }} as rune_depth,
    depths.rune_e8 as rune_depth_e8,
    {{ units('depths.synth_e8') }} as synth_depth,
    depths.synth_e8 as synth_depth_e8,
    depths.rune_e8::numeric / nullif(depths.asset_e8, 0) as asset_price,
    depths.rune_e8::numeric / nullif(depths.asset_e8, 0) * prices.rune_price_usd as asset_price_usd
from {{ source('midgard', 'block_pool_depths') }} as depths
inner join {{ source('midgard', 'block_log') }} as blocks
    on blocks.timestamp = depths.block_timestamp
left join {{ ref('core__rune_price') }} as prices
    on prices.block_height = blocks.height
