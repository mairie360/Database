#!/bin/bash
set -e

echo "🚀 Nettoyage complet..."
docker compose -f docker-compose-test.yml down -v --remove-orphans

echo "🚀 Lancement des tests..."
# IMPORTANT : On ne met SURTOUT PAS --abort-on-container-exit ici
# On utilise uniquement --exit-code-from tester
docker compose -f docker-compose-test.yml up --build --exit-code-from tester

# Upgrade test (MAIR-413): the release deployed in prod, a data set, then HEAD.
# Bump UPGRADE_BASELINE with the prod liquibase image tag in
# Devops/Deploiment (clusters/mairie360/instances/prod/values.yaml).
UPGRADE_BASELINE="${UPGRADE_BASELINE:-v1.3.0}"

echo "🚀 Upgrade test from $UPGRADE_BASELINE..."
if ! git rev-parse -q --verify "refs/tags/$UPGRADE_BASELINE" >/dev/null; then
    # CI checkouts are shallow and carry no tags.
    git fetch --depth 1 origin "refs/tags/$UPGRADE_BASELINE:refs/tags/$UPGRADE_BASELINE"
fi
rm -rf .upgrade-baseline
mkdir -p .upgrade-baseline
git archive "$UPGRADE_BASELINE" liquibase | tar -x -C .upgrade-baseline

docker compose -f docker-compose-upgrade.yml down -v --remove-orphans
docker compose -f docker-compose-upgrade.yml up --build --exit-code-from tester
