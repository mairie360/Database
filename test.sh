#!/bin/bash
set -e

echo "🚀 Nettoyage complet..."
docker compose -f docker-compose-test.yml down -v --remove-orphans

echo "🚀 Lancement des tests..."
# IMPORTANT : On ne met SURTOUT PAS --abort-on-container-exit ici
# On utilise uniquement --exit-code-from tester
docker compose -f docker-compose-test.yml up --build --exit-code-from tester