{#- Raw 1e-8 chain amount (or an expression of them) to real units, exact to 8 decimals. -#}
{% macro units(column) -%}
    round(({{ column }})::numeric / 100000000, 8)
{%- endmacro %}

{#- Midgard nanosecond timestamp to a UTC timestamp. -#}
{% macro block_time(column) -%}
    to_timestamp({{ column }}::numeric / 1000000000)
{%- endmacro %}

{#- Midgard nanosecond timestamp to a UTC date. -#}
{% macro block_day(column) -%}
    (to_timestamp({{ column }}::numeric / 1000000000) at time zone 'UTC')::date
{%- endmacro %}

{#- Midgard event ids are block_height * 1e10 + position in the block. -#}
{% macro block_height(event_id_column) -%}
    ({{ event_id_column }} / 10000000000)
{%- endmacro %}

{#- Pool an asset trades against: BTC/BTC (synth), BTC~BTC (trade) and BTC-BTC (secured) all map to BTC.BTC. -#}
{% macro pool_of(asset_column) -%}
    case
        when {{ asset_column }} like '%.%' then {{ asset_column }}
        else regexp_replace({{ asset_column }}, '^([^/~-]+)[/~-]', '\1.')
    end
{%- endmacro %}

{#- Swap memos have the form SWAP:ASSET:DESTINATION:LIMIT:AFFILIATES:FEES (prefix SWAP, s or =). -#}
{% macro swap_memo_field(memo_column, position) -%}
    case
        when lower(split_part({{ memo_column }}, ':', 1)) in ('swap', 's', '=')
            then nullif(split_part({{ memo_column }}, ':', {{ position }}), '')
    end
{%- endmacro %}
