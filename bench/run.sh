#!/bin/bash
# Schema load test. For each data scale (1 then 2), migrates an empty database,
# loads bench/seed.sql and runs every bench/scripts/*.sql with pgbench, then
# checks each script against bench/thresholds.conf:
#   - blocks: shared/local/temp blocks touched per transaction at scale 1,
#     from pg_stat_statements (top-level statements only). It depends on the
#     plans and the data, not on the machine, so the threshold can be strict;
#   - growth: blocks per transaction at scale 2 / at scale 1. Doubling the
#     data must not double the work: a query that reads ~2x more blocks scans
#     the data instead of using an index and will not hold as the town grows;
#   - ms: average latency at scale 1, a loose safety net (CPU, lock waits)
#     since it depends on the machine.
# Exits non-zero on any breach.
#   bench/run.sh [--quick] [--duration 10] [--clients 8]
# --quick runs scale 1 only (no growth check), to iterate locally.
set -euo pipefail
cd "$(dirname "$0")"

SCALES="1 2" DURATION=10 CLIENTS=8
while [ $# -gt 0 ]; do
    case "$1" in
        --quick) SCALES="1" ;;
        --duration) DURATION="$2"; shift ;;
        --clients) CLIENTS="$2"; shift ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
    shift
done

DC="docker compose -f docker-compose-bench.yml"
PSQL="$DC exec -T database psql -U postgres -d core -v ON_ERROR_STOP=1 -P pager=off"
mkdir -p results
rm -f results/*

declare -A BLOCKS MS TPS FAILED

for scale in $SCALES; do
    echo "=== scale $scale: migrate + seed ==="
    $DC down -v --remove-orphans
    $DC up -d --wait database
    $DC run --rm --build migrate
    $PSQL -qc 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements;'
    $PSQL -v scale="$scale" < seed.sql > "results/seed-$scale.log"
    $DC cp scripts database:/bench-scripts >/dev/null

    if [ "$scale" = 1 ]; then
        echo "--- static lint (informational, the blocking rules are in tests/30_schema_lint_test.sql) ---"
        $PSQL < lint.sql > results/lint.txt
        grep -cvE '^ *(rule|-|\()' results/lint.txt | xargs echo "findings:"
    fi

    echo "=== scale $scale: pgbench, ${CLIENTS} clients, ${DURATION}s per script ==="
    for s in scripts/*.sql; do
        name=$(basename "$s" .sql)
        $PSQL -qAtc 'SELECT pg_stat_statements_reset();' >/dev/null
        out=$($DC exec -T database pgbench -U postgres -d core -n -M prepared -D scale="$scale" \
              -c "$CLIENTS" -j 4 -T "$DURATION" -f "/bench-scripts/$name.sql" 2>&1) || true
        echo "$out" > "results/pgbench-$name-$scale.log"
        txns=$(echo "$out" | sed -n 's/^number of transactions actually processed: \([0-9]*\).*/\1/p')
        blocks=""
        if [ -n "$txns" ] && [ "$txns" -gt 0 ]; then
            blocks=$($PSQL -qAt -c "
                SELECT round(sum(shared_blks_hit + shared_blks_read + local_blks_hit + local_blks_read
                                 + temp_blks_read + temp_blks_written) / $txns::numeric, 1)
                FROM pg_stat_statements
                WHERE toplevel AND dbid = (SELECT oid FROM pg_database WHERE datname = 'core')
                  AND query NOT ILIKE '%pg_stat_statements%'")
        fi
        BLOCKS[$name-$scale]=$blocks
        MS[$name-$scale]=$(echo "$out" | sed -n 's/^latency average = \([0-9.]*\) ms/\1/p')
        TPS[$name-$scale]=$(echo "$out" | sed -n 's/^tps = \([0-9.]*\).*/\1/p')
        FAILED[$name-$scale]=$(echo "$out" | sed -n 's/^number of failed transactions: \([0-9]*\).*/\1/p')
        printf '  %-28s %10s blocks/txn %10s ms\n' "$name" "${blocks:-?}" "${MS[$name-$scale]:-?}"
    done
done

# Compare with thresholds.conf: <script> <max blocks/txn> <max growth> <max ms>
le() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a <= b) }'; }
status=0
echo
printf '%-26s %9s %9s %7s %8s | %9s %7s %7s | %s\n' script blocks@1 blocks@2 growth "ms@1" \
    "max blk" "max gr" "max ms" result | tee results/summary.txt
for s in scripts/*.sql; do
    name=$(basename "$s" .sql)
    read -r max_blocks max_growth max_ms < <(awk -v n="$name" '$1 == n { print $2, $3, $4 }' thresholds.conf) || true
    b1=${BLOCKS[$name-1]:-} b2=${BLOCKS[$name-2]:-} ms=${MS[$name-1]:-} growth=""
    [ -n "$b1" ] && [ -n "$b2" ] && growth=$(awk -v a="$b2" -v b="$b1" 'BEGIN { printf "%.2f", (b > 0 ? a / b : 0) }')
    fails=()
    if [ -z "${max_blocks:-}" ]; then
        fails+=("no threshold")
    else
        for sc in $SCALES; do
            [ -n "${BLOCKS[$name-$sc]:-}" ] || fails+=("pgbench error at scale $sc")
            [ "${FAILED[$name-$sc]:-0}" = 0 ] || fails+=("failed transactions at scale $sc")
        done
        [ -z "$b1" ] || le "$b1" "$max_blocks" || fails+=("blocks")
        [ -z "$growth" ] || le "$growth" "$max_growth" || fails+=("growth")
        [ -z "$ms" ] || le "$ms" "$max_ms" || fails+=("latency")
    fi
    result="ok"
    if [ ${#fails[@]} -gt 0 ]; then result="FAIL ($(IFS=,; echo "${fails[*]}"))"; status=1; fi
    printf '%-26s %9s %9s %7s %8s | %9s %7s %7s | %s\n' "$name" "${b1:-?}" "${b2:--}" "${growth:--}" \
        "${ms:-?}" "${max_blocks:-?}" "${max_growth:-?}" "${max_ms:-?}" "$result" | tee -a results/summary.txt
done

if [ "$status" != 0 ]; then
    echo "❌ At least one script breaches bench/thresholds.conf (see results/summary.txt)."
fi
exit "$status"
