#!/bin/bash
# Schema load test: migrate, seed, run each pgbench script, compare its average
# latency with bench/thresholds.conf, report. Exits non-zero on any breach.
#   bench/run.sh [--reuse] [--duration 15] [--clients 8] [--scale 1]
# --reuse skips the migration and the seed (database left up by a previous run).
set -euo pipefail
cd "$(dirname "$0")"

REUSE=0 DURATION=15 CLIENTS=8 SCALE=1
while [ $# -gt 0 ]; do
    case "$1" in
        --reuse) REUSE=1 ;;
        --duration) DURATION="$2"; shift ;;
        --clients) CLIENTS="$2"; shift ;;
        --scale) SCALE="$2"; shift ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
    shift
done

DC="docker compose -f docker-compose-bench.yml"
PSQL="$DC exec -T database psql -U postgres -d core -v ON_ERROR_STOP=1 -P pager=off"
mkdir -p results

if [ "$REUSE" = 0 ]; then
    $DC down -v --remove-orphans
    $DC up -d --wait database
    $DC run --rm --build migrate
    $PSQL -qc 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements;'
    echo "--- seeding (scale $SCALE) ---"
    $PSQL -v scale="$SCALE" < seed.sql > results/seed.log
fi

echo "--- static lint (informational, the blocking rules are in tests/30_schema_lint_test.sql) ---"
$PSQL < lint.sql > results/lint.txt
grep -cvE '^ *(rule|-|\()' results/lint.txt | xargs echo "findings:"

$DC cp scripts database:/bench-scripts >/dev/null
$PSQL -qc 'SELECT pg_stat_statements_reset();' >/dev/null

echo "--- pgbench: ${CLIENTS} clients, ${DURATION}s per script ---"
status=0
printf '%-28s %10s %10s %10s %8s  %s\n' script tps "avg ms" "max ms" failed result | tee results/pgbench.txt
for s in scripts/*.sql; do
    name=$(basename "$s" .sql)
    max=$(awk -v n="$name" '$1 == n { print $2 }' thresholds.conf)
    out=$($DC exec -T database pgbench -U postgres -d core -n -M prepared \
          -c "$CLIENTS" -j 4 -T "$DURATION" -f "/bench-scripts/$name.sql" 2>&1) || true
    echo "$out" > "results/pgbench-$name.log"
    tps=$(echo "$out" | sed -n 's/^tps = \([0-9.]*\).*/\1/p')
    lat=$(echo "$out" | sed -n 's/^latency average = \([0-9.]*\) ms/\1/p')
    failed=$(echo "$out" | sed -n 's/^number of failed transactions: \([0-9]*\).*/\1/p')
    if [ -z "$max" ]; then
        result="FAIL (no threshold in thresholds.conf)"
    elif [ -z "$lat" ]; then
        result="FAIL (pgbench error, see results/pgbench-$name.log)"
    elif [ "${failed:-0}" != 0 ]; then
        result="FAIL (failed transactions)"
    elif awk -v l="$lat" -v m="$max" 'BEGIN { exit !(l > m) }'; then
        result="FAIL (over threshold)"
    else
        result="ok"
    fi
    [ "$result" = ok ] || status=1
    printf '%-28s %10s %10s %10s %8s  %s\n' "$name" "${tps:-?}" "${lat:-?}" "${max:-?}" "${failed:-?}" "$result" \
        | tee -a results/pgbench.txt
    [ "$result" = ok ] || tail -5 "results/pgbench-$name.log"
done

echo "--- top statements by total time ---"
$PSQL < report.sql | tee results/report.txt

if [ "$status" != 0 ]; then
    echo "❌ At least one script is over its threshold or failed (bench/thresholds.conf)."
fi
exit "$status"
