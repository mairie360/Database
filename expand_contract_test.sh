#!/bin/bash
# Expand/contract check of the migrations: no changeset newer than the release deployed in prod
# may drop, rename or tighten what that release's APIs still use, so that the APIs can be rolled
# back without restoring the database (tests/expand_contract/check_expand_contract.py).
# Run by ./test.sh before the docker stacks.
#
# The baseline is the newest vX.Y.Z tag: tags are only cut by promote-prod, so it is the release
# in prod. EXPAND_CONTRACT_BASELINE=vX.Y.Z overrides it.
set -euo pipefail
cd "$(dirname "$0")"

# CI checkouts are shallow and carry no tags: the check needs every release tag (marker
# validation) and the baseline's tree.
git fetch -q --depth 1 origin 'refs/tags/v*:refs/tags/v*'

baseline="${EXPAND_CONTRACT_BASELINE:-$(git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)}"
if [ -z "$baseline" ]; then
    echo "No release tag found: cannot run the expand/contract check" >&2
    exit 1
fi

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/expand_contract -p '*_test.py'
PYTHONDONTWRITEBYTECODE=1 python3 tests/expand_contract/check_expand_contract.py --baseline "$baseline"
