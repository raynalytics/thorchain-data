{#- Models go into the schema named in their folder config (events, core, daily, legacy) as is, without the target schema prefixed. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ custom_schema_name | trim if custom_schema_name is not none else target.schema }}
{%- endmacro %}
