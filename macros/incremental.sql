{#- Helpers for incremental models. Each model keeps its own high-water mark (the highest block it
    holds) and reads Midgard rows after it by the raw block_timestamp, which Midgard's tables are
    partitioned and indexed on. -#}

{#- First value of a query, run at compile time. -#}
{% macro scalar(query) -%}
    {%- if not execute -%}
        {{- return(none) -}}
    {%- endif -%}
    {%- set result = run_query(query) -%}
    {{- return(result.columns[0].values()[0]) -}}
{%- endmacro %}

{#- Highest block height in the model's existing table, or -1 when it is empty. -#}
{% macro high_water_block(column='block_height') -%}
    {{- return(scalar('select coalesce(max(' ~ column ~ '), -1) from ' ~ this)) -}}
{%- endmacro %}

{#- Midgard nanosecond timestamp of a block (of the highest block at or below it), or -1. -#}
{% macro block_timestamp_ns(height) -%}
    {{- return(scalar("select coalesce(max(timestamp), -1) from " ~ source('midgard', 'block_log') ~ " where height <= " ~ height)) -}}
{%- endmacro %}

{#- A Midgard table limited to rows matching a condition on its own columns, e.g. block_timestamp. -#}
{% macro midgard_rows(table, condition) -%}
    (select * from {{ source('midgard', table) }} where {{ condition }}) as {{ table }}
{%- endmacro %}

{#- First day a daily model recomputes: the last day it holds (which may have been partial), or the
    start day of any swap that has gained legs since then (streaming swaps run over several days).
    For an empty table, the first indexed day. -#}
{% macro daily_start_day() -%}
    {%- set last_day = scalar('select max(day) from ' ~ this) -%}
    {%- if last_day is none -%}
        {{- return(scalar('select coalesce(min(day), current_date) from ' ~ ref('core__blocks'))) -}}
    {%- endif -%}
    {{- return(scalar(
        "select least(date '" ~ last_day ~ "', (select min(day) from " ~ ref('core__swaps')
        ~ " where end_block_height >= (select min(block_height) from " ~ ref('core__blocks')
        ~ " where day >= date '" ~ last_day ~ "')))"
    )) -}}
{%- endmacro %}

{#- First block on or after a day (a SQL expression). -#}
{% macro first_block_of(day_expression) -%}
    (select coalesce(min(block_height), 9223372036854775807) from {{ ref('core__blocks') }} where day >= {{ day_expression }})
{%- endmacro %}

{#- Midgard nanosecond timestamp of the start of a UTC day (a SQL expression). -#}
{% macro day_start_ns(day_expression) -%}
    (extract(epoch from ({{ day_expression }})::timestamp) * 1000000000)::bigint
{%- endmacro %}
