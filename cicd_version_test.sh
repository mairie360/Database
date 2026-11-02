#!/bin/bash
# MAIR-771: the GDPR inventory of mairie360/CICD (`gdpr_inventory` on promote-prod) only exists from
# CICD v4.12.0. Fails when a workflow of this repo falls behind that release, or when the workflows
# disagree on the version they call (the `uses:` ref and `cicd_version` must stay equal, since the
# actions are checked out at `cicd_version`). Run by ./test.sh before the docker stacks.
set -euo pipefail
cd "$(dirname "$0")"

MIN_CICD="v4.12.0"
WORKFLOWS=(cicd.yml gdpr-pr.yml promote-staging.yml promote-prod.yml)
status=0
expected=""

# Every CICD version a workflow names: the `uses:` refs (the `# vX.Y.Z` comment of a SHA pin)
# and the `cicd_version:` inputs.
cicd_versions() {
  sed -nE \
    -e 's/^[[:space:]]*uses:[[:space:]]*mairie360\/CICD\/[^@]*@[^[:space:]#]+[[:space:]]*#[[:space:]]*([^[:space:]]+).*/\1/p;t' \
    -e 's/^[[:space:]]*uses:[[:space:]]*mairie360\/CICD\/[^@]*@([^[:space:]#]+).*/\1/p;t' \
    -e 's/^[[:space:]]*cicd_version:[[:space:]]*([^[:space:]#]+).*/\1/p' \
    "$1"
}

for name in "${WORKFLOWS[@]}"; do
  versions="$(cicd_versions ".github/workflows/$name")"
  if [ -z "$versions" ]; then
    echo "MAIR-771: $name does not call mairie360/CICD"
    status=1
    continue
  fi
  while read -r version; do
    [ -z "$expected" ] && expected="$version"
    if [ "$version" != "$expected" ]; then
      echo "MAIR-771: $name pins CICD $version, expected $expected everywhere"
      status=1
    fi
  done <<< "$versions"
done

if ! [[ "$expected" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "MAIR-771: CICD pin '$expected' is not vX.Y.Z"
  status=1
elif [ "$(printf '%s\n%s\n' "$expected" "$MIN_CICD" | sort -V | head -n 1)" != "$MIN_CICD" ]; then
  echo "MAIR-771: CICD $expected predates $MIN_CICD: no gdpr_inventory on promote-prod"
  status=1
fi

if ! grep -qE 'secrets: inherit|ANTHROPIC_API_KEY:' .github/workflows/promote-prod.yml; then
  echo "MAIR-771: promote-prod.yml does not pass ANTHROPIC_API_KEY: the AI review of the inventory is skipped"
  status=1
fi

[ "$status" -eq 0 ] && echo "MAIR-771: every workflow calls CICD $expected"
exit "$status"
