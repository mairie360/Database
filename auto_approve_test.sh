#!/usr/bin/env bash
# The Renovate auto-approval is the reusable workflow of mairie360/CICD, which approves a Renovate
# pull request only while Renovate alone wrote and pushed its branch: this repository only calls
# it, with the same release on both pins and no permission beyond `pull-requests: write`.
set -u
root="$(cd "$(dirname "$0")/." && pwd)" || exit 1
python3 - "$root/.github/workflows/auto-approve.yml" <<'PY' || exit 1
import re
import sys

live = [line.split(" #")[0].rstrip() for line in open(sys.argv[1], encoding="utf-8").read().split("\n")]
stripped = [line.strip() for line in live]
failures = []
uses = [m.group(1) for m in (re.match(r"^\s*uses:\s*(\S+)$", line) for line in live) if m]
tag = None
if len(uses) != 1:
    failures.append(f"MAIR-685 one call and no local step, found {uses}")
else:
    m = re.match(r"^mairie360/CICD/\.github/workflows/auto-approve\.yml@(v\d+\.\d+\.\d+)$", uses[0])
    if not m:
        failures.append(f"MAIR-685 calls the auto-approval of mairie360/CICD on a release tag: {uses[0]}")
    else:
        tag = m.group(1)
if tag and f"cicd_version: {tag}" not in stripped:
    failures.append(f"MAIR-685 cicd_version is {tag} too")
if any(re.match(r"^\s*steps:", line) for line in live):
    failures.append("MAIR-685 no local step")
if "permissions: {}" not in live:
    failures.append("MAIR-685 no default token scope (permissions: {})")
scopes = [line for line in stripped if re.match(r"^[a-z-]+: (read|write)$", line)]
if scopes != ["pull-requests: write"]:
    failures.append(f"MAIR-685 only pull-requests: write, found {scopes}")
if "types: [opened, reopened, synchronize]" not in stripped:
    failures.append("MAIR-685 runs on every push to the branch")
for failure in failures:
    print(f"FAIL {failure}")
if failures:
    sys.exit(1)
print("ok - MAIR-685 the auto-approval is the call to mairie360/CICD")
PY
