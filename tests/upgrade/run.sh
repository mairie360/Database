#!/bin/sh
# Upgrade test (MAIR-413): the path a real instance takes on deploy.
#
#   1. /baseline/liquibase (the release deployed in prod) on an empty database,
#   2. tests/upgrade/seed.sql, data written against that baseline schema,
#   3. HEAD without admin credentials: must fail while the template admin
#      account is still there,
#   4. HEAD with admin credentials, then a second time (runAlways replay),
#   5. rollback to the previous release tag (undoes the newest git tag's
#      releases/vX.Y.Z folder) and update again,
#   6. pg_prove tests/upgrade/*_test.sql on the result.
#
# Runs in the tester container of docker-compose-upgrade.yml.
set -eu

# Liquibase resolves `sqlFile path="NN__x.sql"` against the search path, so
# every release folder of the changelog tree is listed (same as the compose
# files). The changelog file names recorded in DATABASECHANGELOG are relative
# to it; the changesets HEAD moved into another folder keep their former path
# as logicalFilePath, so the baseline and HEAD trees match.
search_path() {
    path="$1"
    for dir in "$1"/releases/*/; do
        path="$path,${dir%/}"
    done
    echo "$path,$1/repeatable"
}

ROLE_PARAMS="-Dcore_api_password=password -Dproject_api_password=password -Dcalendar_api_password=password -Dmessage_api_password=password -Delearning_api_password=password"
ADMIN_EMAIL='mayor@upgrade.example'
ADMIN_PASSWORD='$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'

liquibase_at() {
    root="$1"
    shift
    LIQUIBASE_SEARCH_PATH="$(search_path "$root")" liquibase --log-level=SEVERE --changelog-file=changelog.xml "$@"
}

echo '--- 1. BASELINE MIGRATION ---'
# shellcheck disable=SC2086
liquibase_at /baseline/liquibase update $ROLE_PARAMS

echo '--- 2. SEEDING BASELINE DATA ---'
psql -v ON_ERROR_STOP=1 -q -f /workspace/tests/upgrade/seed.sql

echo '--- 3. HEAD WITHOUT ADMIN CREDENTIALS (must fail) ---'
# shellcheck disable=SC2086
if liquibase_at /workspace/liquibase update $ROLE_PARAMS > /tmp/no-credentials.log 2>&1; then
    cat /tmp/no-credentials.log
    echo 'FAIL: HEAD migrated without admin credentials while the template admin account exists'
    exit 1
fi
if ! grep -q 'admin_email and admin_password must be supplied' /tmp/no-credentials.log; then
    cat /tmp/no-credentials.log
    echo 'FAIL: HEAD failed for another reason than the missing admin credentials'
    exit 1
fi
echo 'Refused as expected.'

echo '--- 4. HEAD WITH ADMIN CREDENTIALS, TWICE ---'
for run in 1 2; do
    echo "run $run"
    # shellcheck disable=SC2086
    liquibase_at /workspace/liquibase update $ROLE_PARAMS \
        -Dadmin_email="$ADMIN_EMAIL" -Dadmin_password="$ADMIN_PASSWORD"
done

echo '--- 5. ROLLBACK TO THE PREVIOUS RELEASE TAG, THEN UPDATE ---'
# The tag before the last one, so the rollback of the newest release runs; the
# last one when HEAD only adds one tag.
rollback_tag="$(psql -At -c "SELECT tag FROM (SELECT tag, orderexecuted FROM databasechangelog WHERE tag IS NOT NULL ORDER BY orderexecuted DESC LIMIT 2) t ORDER BY orderexecuted LIMIT 1")"
echo "rolling back to $rollback_tag"
# shellcheck disable=SC2086
liquibase_at /workspace/liquibase rollback --tag="$rollback_tag" $ROLE_PARAMS
# shellcheck disable=SC2086
liquibase_at /workspace/liquibase update $ROLE_PARAMS \
    -Dadmin_email="$ADMIN_EMAIL" -Dadmin_password="$ADMIN_PASSWORD"

# The runAlways changesets (security/api_*) are always listed as pending.
# The parameters are passed because they are part of the checksum of the
# changesets that use them.
# shellcheck disable=SC2086
pending="$(liquibase_at /workspace/liquibase status --verbose $ROLE_PARAMS \
    -Dadmin_email="$ADMIN_EMAIL" -Dadmin_password="$ADMIN_PASSWORD" 2>&1 \
    | grep '::' | grep -v -e '::rep-security-api-roles::' -e '::rep-security-api-grants::' || true)"
if [ -n "$pending" ]; then
    echo "$pending"
    echo 'FAIL: changesets are still pending after the upgrade'
    exit 1
fi

echo '--- 6. CHECKING THE UPGRADED DATABASE ---'
psql -q -c 'CREATE EXTENSION IF NOT EXISTS pgtap;'
pg_prove /workspace/tests/upgrade/*_test.sql
