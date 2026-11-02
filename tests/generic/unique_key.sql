{#- Fails for every combination of the given columns that appears more than once. -#}
{% test unique_key(model, columns) %}
select
    {{ columns | join(', ') }},
    count(*) as row_count
from {{ model }}
group by {{ columns | join(', ') }}
having count(*) > 1
{% endtest %}
