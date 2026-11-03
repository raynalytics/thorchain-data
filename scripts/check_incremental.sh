#!/usr/bin/env bash
# Checks that incremental runs give exactly the tables a full rebuild gives, on the sample data.
#
#   1. Copies an empty Midgard database to a sample database and loads sample_data/stage_1.sql.
#   2. Builds and tests everything from scratch.
#   3. Loads sample_data/stage_2.sql (later blocks, in which streaming swaps SPR and SFL finish, SFL
#      with no new leg) and builds and tests again, incrementally.
#   4. Keeps a copy of the core and daily tables, rebuilds everything from scratch, tests again and
#      compares every table row for row with the copy.
#
# Settings (environment variables):
#   DBT_TARGET           dbt target pointing at SAMPLE_DB (default: sample)
#   SAMPLE_DB            database to create and fill (default: midgard_sample); it is dropped and
#                        recreated, and dropped again at the end unless KEEP_SAMPLE_DB=1
#   MIDGARD_TEMPLATE_DB  empty Midgard database to copy (default: midgard_latest)
#   PSQL                 psql command (default: psql), e.g. "docker exec -i timescale psql -U midgard"
#   DBT                  dbt command (default: dbt)
set -euo pipefail
cd "$(dirname "$0")/.."

PSQL=${PSQL:-psql}
DBT=${DBT:-dbt}
TARGET=${DBT_TARGET:-sample}
DB=${SAMPLE_DB:-midgard_sample}
TEMPLATE=${MIDGARD_TEMPLATE_DB:-midgard_latest}

sql() { $PSQL -v ON_ERROR_STOP=1 -q -d "$1"; }
value() { echo "$2" | $PSQL -v ON_ERROR_STOP=1 -At -d "$1"; }

load() {
    sql "$DB" < "$1"
    # Midgard's own daily aggregates, which the swaps_match_midgard test compares against
    for aggregate in swaps_5min swaps_hour swaps_day; do
        echo "call refresh_continuous_aggregate('midgard_agg.$aggregate', null, null);" | sql "$DB"
    done
}

expect() {
    local actual
    actual=$(value "$DB" "$1")
    if [ "$actual" != "$2" ]; then
        echo "FAIL: $1 returned '$actual', expected '$2'" >&2
        exit 1
    fi
}

printf 'drop database if exists %s;\ncreate database %s template %s;\n' "$DB" "$DB" "$TEMPLATE" | sql postgres

echo "== Stage 1: full build"
load sample_data/stage_1.sql
$DBT build --target "$TARGET" --full-refresh
expect "select status || ' ' || streaming_count from core.swaps where tx_id = 'SPR'" "in_progress 2"
expect "select status || ' ' || streaming_count from core.swaps where tx_id = 'SFL'" "in_progress 1"

echo "== Stage 2: incremental build"
load sample_data/stage_2.sql
$DBT build --target "$TARGET"
expect "select status || ' ' || streaming_count from core.swaps where tx_id = 'SPR'" "completed 4"
expect "select status || ' ' || streaming_count from core.swaps where tx_id = 'SFL'" "partly_refunded 2"

tables=$(value "$DB" "select table_schema || '.' || table_name from information_schema.tables
    where table_schema in ('core', 'daily') and table_type = 'BASE TABLE' order by 1")
{
    echo "drop schema if exists incremental_result cascade; create schema incremental_result;"
    for table in $tables; do
        echo "create table incremental_result.${table/./__} as table $table;"
    done
} | sql "$DB"

echo "== Full rebuild"
$DBT build --target "$TARGET" --full-refresh

echo "== Comparing incremental and full tables"
failed=0
for table in $tables; do
    differences=$(value "$DB" "select
        (select count(*) from (table incremental_result.${table/./__} except all table $table) as only_incremental)
        + (select count(*) from (table $table except all table incremental_result.${table/./__}) as only_full)")
    rows=$(value "$DB" "select count(*) from $table")
    if [ "$differences" != "0" ]; then
        echo "DIFFERENT  $table ($differences rows differ)"
        failed=1
    else
        echo "identical  $table ($rows rows)"
    fi
done

if [ "${KEEP_SAMPLE_DB:-0}" != "1" ]; then
    echo "drop database $DB;" | sql postgres
fi
exit $failed
