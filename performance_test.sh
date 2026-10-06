#!/bin/bash
# Run by mairie360/CICD (database_cicd.yml, job performance_tests) between
# release-dev and release-staging: a breach of bench/thresholds.conf blocks the
# promotion to staging. Can be run by hand the same way (needs Docker).
set -euo pipefail
cd "$(dirname "$0")"

status=0
bench/run.sh "$@" || status=$?
docker compose -f bench/docker-compose-bench.yml down -v --remove-orphans
exit "$status"
