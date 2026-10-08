#!/usr/bin/env python3
"""Loads gdpr/inventory.yaml into the test database (MAIR-286).

Prints SQL that creates `gdpr_test.inventory`, one row per column of the inventory, so that the
pgTAP tests (tests/36_gdpr_schema_test.sql) check the schema against the decisions written in the
inventory instead of a copy of them. Run by docker-compose-test.yml after the migrations:

    python3 tests/gdpr/inventory_to_sql.py gdpr/inventory.yaml | psql ...

The schema `gdpr_test` only exists in the test database; the schema lint and the coverage only
look at `public`. The format of the inventory is checked by the CICD inventory gate (MAIR-285);
this script only refuses what the tests cannot read.
"""
import sys

import yaml


def literal(value):
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    return "'" + str(value).replace("'", "''") + "'"


def rows(inventory):
    for table, entry in sorted(inventory["tables"].items()):
        audited = bool(entry.get("audited", False))
        for column, spec in sorted((entry.get("personal") or {}).items()):
            yield (table, column, True, spec["category"], spec["erasure"], spec["visibility"],
                   spec.get("audit_log", True), audited)
        for column in sorted(entry.get("not_personal") or []):
            yield (table, column, False, None, None, None, True, audited)


def main(path):
    with open(path, encoding="utf-8") as handle:
        inventory = yaml.safe_load(handle)
    if not isinstance(inventory, dict) or inventory.get("version") != 1 or "tables" not in inventory:
        sys.exit(f"{path}: not a version 1 inventory")
    print("DROP SCHEMA IF EXISTS gdpr_test CASCADE;")
    print("CREATE SCHEMA gdpr_test;")
    print(
        "CREATE TABLE gdpr_test.inventory (table_name TEXT NOT NULL, column_name TEXT NOT NULL, "
        "personal BOOLEAN NOT NULL, category TEXT, erasure TEXT, visibility TEXT, "
        "audit_log BOOLEAN NOT NULL, audited BOOLEAN NOT NULL, PRIMARY KEY (table_name, column_name));"
    )
    values = [f"({', '.join(literal(v) for v in row)})" for row in rows(inventory)]
    print("INSERT INTO gdpr_test.inventory VALUES\n  " + ",\n  ".join(values) + ";")
    print("GRANT USAGE ON SCHEMA gdpr_test TO PUBLIC;")
    print("GRANT SELECT ON gdpr_test.inventory TO PUBLIC;")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: inventory_to_sql.py <gdpr/inventory.yaml>")
    main(sys.argv[1])
