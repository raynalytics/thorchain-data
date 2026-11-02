{#- Model files are named <layer>__<table>.sql so names stay unique across layers; the table is created as <table>. -#}
{% macro generate_alias_name(custom_alias_name=none, node=none) -%}
    {%- if custom_alias_name -%}
        {{ custom_alias_name | trim }}
    {%- else -%}
        {{ node.name.split('__')[-1] }}
    {%- endif -%}
{%- endmacro %}
