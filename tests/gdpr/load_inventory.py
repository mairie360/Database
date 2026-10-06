#!/usr/bin/env python3
"""Turn gdpr/inventory.yaml into SQL that loads it into gdpr.inventory (MAIR-285).

Usage: load_inventory.py <inventory.yaml> | psql -v ON_ERROR_STOP=1 ...

The format is checked here, with one readable message per problem; the comparison with the
migrated schema is done by tests/35_gdpr_inventory_test.sql. Exits 1 without printing any SQL
when the file is invalid, so the test run stops before pg_prove.
"""
import sys

import yaml

CATEGORIES = {
    "identifier", "identity", "contact", "credentials", "connection",
    "account", "activity", "content", "preferences",
}
ERASURES = {"delete", "anonymize", "keep"}
VISIBILITIES = {"self", "members", "directory", "admin", "internal"}
PERSONAL_KEYS = {"category", "erasure", "visibility", "audit_log", "note"}
TABLE_KEYS = {"audited", "personal", "not_personal"}


def literal(value):
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    return "'" + str(value).replace("'", "''") + "'"


def check(inventory):
    errors = []
    rows = []
    if not isinstance(inventory, dict) or inventory.get("version") != 1:
        return ["the file must be a mapping with `version: 1`"], rows
    tables = inventory.get("tables")
    if not isinstance(tables, dict) or not tables:
        return ["`tables` must be a non-empty mapping"], rows
    for table, spec in tables.items():
        if not isinstance(spec, dict):
            errors.append(f"{table}: must be a mapping")
            continue
        for key in sorted(set(spec) - TABLE_KEYS):
            errors.append(f"{table}: unknown key `{key}`")
        audited = spec.get("audited", False)
        if not isinstance(audited, bool):
            errors.append(f"{table}: `audited` must be true or false")
        personal = spec.get("personal") or {}
        not_personal = spec.get("not_personal") or []
        if not isinstance(personal, dict):
            errors.append(f"{table}: `personal` must map each column to its classification")
            personal = {}
        if not isinstance(not_personal, list):
            errors.append(f"{table}: `not_personal` must be a list of columns")
            not_personal = []
        if not personal and not not_personal:
            errors.append(f"{table}: lists no column")
        for column in sorted(set(personal) & set(not_personal)):
            errors.append(f"{table}.{column}: listed both as personal and not personal")
        if len(set(not_personal)) != len(not_personal):
            errors.append(f"{table}: a column is listed twice in `not_personal`")
        for column, entry in personal.items():
            name = f"{table}.{column}"
            if not isinstance(entry, dict):
                errors.append(f"{name}: must be a mapping with category, erasure and visibility")
                continue
            for key in sorted(set(entry) - PERSONAL_KEYS):
                errors.append(f"{name}: unknown key `{key}`")
            if entry.get("category") not in CATEGORIES:
                errors.append(f"{name}: category must be one of {', '.join(sorted(CATEGORIES))}")
            if entry.get("erasure") not in ERASURES:
                errors.append(f"{name}: erasure must be one of {', '.join(sorted(ERASURES))}")
            if entry.get("visibility") not in VISIBILITIES:
                errors.append(f"{name}: visibility must be one of {', '.join(sorted(VISIBILITIES))}")
            audit_log = entry.get("audit_log", True)
            if not isinstance(audit_log, bool):
                errors.append(f"{name}: audit_log must be true or false")
            elif not audit_log and audited is not True:
                errors.append(f"{name}: audit_log only applies to an audited table")
            note = entry.get("note")
            if note is not None and (not isinstance(note, str) or not note.strip()):
                errors.append(f"{name}: note must be a non-empty string")
            rows.append((table, column, True, entry.get("category"), entry.get("erasure"),
                         entry.get("visibility"), audit_log, note))
        for column in not_personal:
            if not isinstance(column, str):
                errors.append(f"{table}: `not_personal` must only hold column names")
                continue
            rows.append((table, column, False, None, None, None, True, None))
    return errors, rows


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: load_inventory.py <inventory.yaml>")
    with open(sys.argv[1], encoding="utf-8") as handle:
        inventory = yaml.safe_load(handle)
    errors, rows = check(inventory)
    if errors:
        print(f"{sys.argv[1]} is invalid:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        sys.exit(1)
    print("SET client_min_messages = warning;")
    print("DROP SCHEMA IF EXISTS gdpr CASCADE;")
    print("CREATE SCHEMA gdpr;")
    print(
        "CREATE TABLE gdpr.inventory (\n"
        "    table_name TEXT NOT NULL,\n"
        "    column_name TEXT NOT NULL,\n"
        "    personal BOOLEAN NOT NULL,\n"
        "    category TEXT,\n"
        "    erasure TEXT,\n"
        "    visibility TEXT,\n"
        "    audit_log BOOLEAN NOT NULL,\n"
        "    note TEXT,\n"
        "    PRIMARY KEY (table_name, column_name)\n"
        ");"
    )
    print("INSERT INTO gdpr.inventory VALUES")
    print(",\n".join("    (" + ", ".join(literal(v) for v in row) + ")" for row in rows) + ";")


if __name__ == "__main__":
    main()
