{#- Fails for every day between the first and last day present (per group, if given) that has no row. -#}
{% test no_missing_days(model, column_name, group_by=none) %}
with present as (
    select distinct
        {% if group_by %}{{ group_by }} as group_key,{% endif %}
        {{ column_name }} as day
    from {{ model }}
),

expected as (
    select
        {% if group_by %}group_key,{% endif %}
        generate_series(min(day), max(day), interval '1 day')::date as day
    from present
    {% if group_by %}group by group_key{% endif %}
)

select expected.*
from expected
left join present
    on present.day = expected.day
    {% if group_by %}and present.group_key = expected.group_key{% endif %}
where present.day is null
{% endtest %}
