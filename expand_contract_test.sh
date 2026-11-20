#!/bin/bash
# Expand/contract check of the migrations: no changeset newer than the release deployed in prod
# may drop, rename or tighten what that release's APIs still use, so that the APIs can be rolled
# back without restoring the database (tests/expand_contract/check_expand_contract.py).
# Run by ./test.sh before the docker stacks.
#
# The baseline is the newest vX.Y.Z tag: a push to main only releases dev (no semantic-release
# there); the tag and its GitHub release are cut by CICD's promote-prod.yml once the Prod
# approval is given, so the newest tag is the release in prod. EXPAND_CONTRACT_BASELINE=vX.Y.Z
# overrides it.
set -euo pipefail
cd "$(dirname "$0")"

# CI checkouts are shallow and carry no tags: the check needs every release tag (marker
# validation) and the baseline's tree. A full clone that already has them is left alone
# (`--depth` would make it shallow), as test.sh does for UPGRADE_BASELINE.
if [ "$(git rev-parse --is-shallow-repository)" = true ] || [ -z "$(git tag --list 'v*')" ] \
    || { [ -n "${EXPAND_CONTRACT_BASELINE:-}" ] \
         && ! git rev-parse -q --verify "refs/tags/$EXPAND_CONTRACT_BASELINE" >/dev/null; }; then
    git fetch -q --depth 1 origin 'refs/tags/v*:refs/tags/v*'
fi

baseline="${EXPAND_CONTRACT_BASELINE:-$(git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)}"
if [ -z "$baseline" ]; then
    echo "No release tag found: cannot run the expand/contract check" >&2
    exit 1
fi

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/expand_contract -p '*_test.py'
PYTHONDONTWRITEBYTECODE=1 python3 tests/expand_contract/check_expand_contract.py --baseline "$baseline"
