#!/usr/bin/env python3
"""MAIR-497: every Redis key shape the platform writes is declared in the `redis` section of
gdpr/inventory.yaml, within its maximum TTL. Same matching as the GDPR simulation of mairie360/CICD
(tests/gdpr/simulation/redis.mjs): `{...}` stands for one segment without `:` nor `/`.

The read cache of mairie360_api_lib (MAIR-524) was missing: the simulation of every API that uses
it failed on `read-cache:…` keys. Exit 0 when every sample key matches one declared prefix.
usage: redis_prefixes_test.py <gdpr/inventory.yaml>
"""
import re
import sys

import yaml

# (sample key, longest TTL the code sets) per key shape written by the APIs and BFFs.
SAMPLES = [
    ("revoked:4f1c2b", 3600),
    ("core-api:jane@example.test/forgot_password_token", 1800),
    ("core-api:0a1b2c/forgot_password_email", 1800),
    ("core-api:42/first_connection_token", 86400),
    ("core-api:0a1b2c/first_connection_id", 86400),
    # mairie360_api_lib read cache: entries per caller and shared, and the namespace generation,
    # with the role prefix of each API that uses it (Redis ACL of an instance, MAIR-267) and
    # without it (test stacks, no ACL).
    ("core-api:read-cache:directory:0:u42:" + "ab" * 32, 300),
    ("core-api:read-cache:directory:generation", 7 * 24 * 3600),
    ("project-api:read-cache:projects:0:u42:" + "ab" * 32, 300),
    ("project-api:read-cache:projects:generation", 7 * 24 * 3600),
    ("calendar-api:read-cache:calendar:9f8e7d6c:shared:" + "cd" * 32, 300),
    ("calendar-api:read-cache:calendar:generation", 7 * 24 * 3600),
    ("read-cache:projects:0:u42:" + "ab" * 32, 300),
    ("read-cache:calendar:9f8e7d6c:shared:" + "cd" * 32, 300),
    ("read-cache:projects:generation", 7 * 24 * 3600),
]


def pattern(prefix: str) -> re.Pattern:
    parts = re.split(r"\{[^}]*\}", prefix)
    return re.compile("^" + "[^:/]+".join(re.escape(p) for p in parts) + "$")


def main(path: str) -> int:
    redis = yaml.safe_load(open(path, encoding="utf-8"))["redis"]
    declared = [(prefix, spec, pattern(prefix)) for prefix, spec in redis.items()]
    failures = []
    for key, ttl in SAMPLES:
        matches = [(prefix, spec) for prefix, spec, rx in declared if rx.match(key)]
        if len(matches) != 1:
            failures.append(f"{key}: matches {len(matches)} declared prefixes (expected 1)")
        elif ttl > matches[0][1]["max_ttl_seconds"]:
            failures.append(f"{key}: TTL {ttl} s above the declared {matches[0][1]['max_ttl_seconds']} s")
    for prefix, spec, _ in declared:
        if "max_ttl_seconds" not in spec or "personal" not in spec:
            failures.append(f"{prefix}: needs `personal` and `max_ttl_seconds`")
    for failure in failures:
        print(f"not ok - {failure}")
    print(f"{len(SAMPLES) - len([f for f in failures if not f.endswith('`max_ttl_seconds`')])}/{len(SAMPLES)} Redis key shapes declared")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
