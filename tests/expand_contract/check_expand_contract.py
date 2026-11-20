#!/usr/bin/env python3
"""Expand/contract check of the Liquibase migrations.

The APIs of the previous release must keep working on the schema of the next one, so that a
release can be rolled back without restoring the database. A migration therefore only *expands*
the schema (new table, nullable or defaulted column, new function, new index). Dropping,
renaming or tightening an element (*contract*) waits for a later release, once no deployed
version still uses it.

This script compares the SQL under ``liquibase/`` with the same tree at the baseline release
(the latest one deployed in prod) and fails on every destructive statement that is new since
then. ``*.rollback.sql`` files are skipped: they undo a release, they never run forward.

A deliberate contract step is accepted when the statement carries a marker naming the release
that shipped the expand step, which must already be released (a tag at or before the baseline):

    -- contract: v3.4.0
    ALTER TABLE tasks DROP COLUMN assigned_to;

A statement that does not break the previous release although it looks destructive (a column
filled by a trigger for the writers that omit it, for example) is accepted with a reason:

    -- expand-safe: the trigger gives the writers that omit it the first status

A marker sits on the statement's line or in the comment lines right above it. Dropping a
function, procedure or view is not destructive when the same file creates it again with the
same signature (the repeatable drop-and-recreate pattern); a table or type recreated in the same
file still loses its data or members, so it counts. A drop of an object the baseline release
never had is not destructive either.

Usage: check_expand_contract.py --baseline vX.Y.Z [--root .]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

SQL_ROOT = "liquibase"

# Statements that break the code of the previous release when they run before it is retired.
# Each pattern stops at the end of the statement (`;`) or of an ALTER TABLE action (`,`).
DESTRUCTIVE = [
    ("drop", re.compile(
        r"\bDROP\s+(?:MATERIALIZED\s+VIEW|TABLE|VIEW|FUNCTION|PROCEDURE|TYPE|SCHEMA|SEQUENCE|DOMAIN)\b[^;]*",
        re.IGNORECASE)),
    ("drop column", re.compile(r"\bDROP\s+COLUMN\b[^;,]*", re.IGNORECASE)),
    ("rename", re.compile(r"\bRENAME\b[^;,]*", re.IGNORECASE)),
    ("type change", re.compile(
        r"\bALTER\s+COLUMN\s+\S+\s+(?:SET\s+DATA\s+)?TYPE\b[^;,]*", re.IGNORECASE)),
    ("set not null", re.compile(r"\bALTER\s+COLUMN\s+\S+\s+SET\s+NOT\s+NULL\b", re.IGNORECASE)),
]
# One level of parentheses inside the action: `NUMERIC(10,2) NOT NULL` is one column.
ADD_COLUMN = re.compile(r"\bADD\s+COLUMN\b(?:[^;,()]|\([^()]*\))*", re.IGNORECASE)
NOT_NULL = re.compile(r"\bNOT\s+NULL\b", re.IGNORECASE)
HAS_VALUE = re.compile(r"\b(?:DEFAULT|GENERATED)\b", re.IGNORECASE)
MARKER = re.compile(r"--.*\bcontract:\s*(v\d+\.\d+\.\d+)\b", re.IGNORECASE)
SAFE_MARKER = re.compile(r"--.*\bexpand-safe:\s*\S", re.IGNORECASE)
DROP_OBJECT = re.compile(
    r"\bDROP\s+(MATERIALIZED\s+VIEW|TABLE|VIEW|FUNCTION|PROCEDURE|TYPE)\s+(?:IF\s+EXISTS\s+)?"
    r"([\w.\"]+)\s*(\()?", re.IGNORECASE)
CREATE_OBJECT = re.compile(
    r"\bCREATE\s+(?:OR\s+REPLACE\s+)?(?:UNLOGGED\s+|TEMP(?:ORARY)?\s+)?"
    r"(MATERIALIZED\s+VIEW|TABLE|VIEW|FUNCTION|PROCEDURE|TYPE)\s+(?:IF\s+NOT\s+EXISTS\s+)?"
    r"([\w.\"]+)\s*(\()?", re.IGNORECASE)
# First words of the built-in types written in several words: an argument starting with one of
# them has no name.
MULTIWORD_TYPES = {"DOUBLE", "CHARACTER", "TIMESTAMP", "TIME", "BIT", "NATIONAL", "INTERVAL"}
TYPE_ALIASES = {
    "INT": "INTEGER", "INT4": "INTEGER", "INT8": "BIGINT", "INT2": "SMALLINT", "BOOL": "BOOLEAN",
    "CHARACTER VARYING": "VARCHAR", "TIMESTAMPTZ": "TIMESTAMP WITH TIME ZONE",
    "FLOAT8": "DOUBLE PRECISION", "DECIMAL": "NUMERIC",
}
# Kinds identified by their whole key: dropping and creating one again in the same file is the
# repeatable pattern. A table or type recreated in place loses its rows or members.
RECREATABLE = {"FUNCTION", "PROCEDURE", "VIEW", "MATERIALIZED VIEW"}
ALTER_TABLE = re.compile(r"\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?([\w.\"]+)",
                         re.IGNORECASE)
SEMVER = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    kind: str
    statement: str
    marker: str | None
    target: str = ""
    safe: bool = False
    exempt: bool = False
    object_drop: bool = False


def _blank_comments(sql: str) -> str:
    """Replaces `--` and `/* */` comments with spaces, keeping every offset in place.

    String literals are kept: a destructive statement inside `EXECUTE '…'` still counts.
    """
    out = list(sql)
    i, n = 0, len(sql)
    in_string = False
    while i < n:
        c = sql[i]
        if in_string:
            if c == "'":
                in_string = False
            i += 1
        elif c == "'":
            in_string = True
            i += 1
        elif sql.startswith("--", i):
            end = sql.find("\n", i)
            end = n if end == -1 else end
            out[i:end] = " " * (end - i)
            i = end
        elif sql.startswith("/*", i):
            end = sql.find("*/", i + 2)
            end = n if end == -1 else end + 2
            out[i:end] = [ch if ch == "\n" else " " for ch in sql[i:end]]
            i = end
        else:
            i += 1
    return "".join(out)


def _normalise(statement: str) -> str:
    return " ".join(statement.split()).upper()


def _marker_lines(lines: list[str], line_index: int) -> list[str]:
    """The statement's line, then the comment block right above it."""
    block = [lines[line_index]]
    i = line_index - 1
    while i >= 0 and lines[i].strip().startswith("--"):
        block.append(lines[i])
        i -= 1
    return block


def _marker(lines: list[str], line_index: int) -> str | None:
    """Release named by a `contract:` marker on the line or in the comment block above it."""
    for line in _marker_lines(lines, line_index):
        found = MARKER.search(line)
        if found:
            return found.group(1)
    return None


def _safe(lines: list[str], line_index: int) -> bool:
    return any(SAFE_MARKER.search(line) for line in _marker_lines(lines, line_index))


def _split_args(args: str) -> list[str]:
    """Top-level arguments; commas and parentheses inside `'…'` literals do not count."""
    parts, depth, current, quoted = [], 0, "", False
    for c in args:
        if c == "'":
            quoted = not quoted  # a doubled quote toggles twice
        elif quoted:
            pass
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if c == "," and depth == 0 and not quoted:
            parts.append(current)
            current = ""
        else:
            current += c
    if current.strip():
        parts.append(current)
    return parts


def _arg_types(args: str) -> tuple[str, ...]:
    """Argument types of a signature, without names, modes, defaults or lengths."""
    types = []
    for arg in _split_args(args):
        arg = re.split(r"\bDEFAULT\b|:=|=", arg, maxsplit=1, flags=re.IGNORECASE)[0]
        arg = re.sub(r"\([^)]*\)", "", arg)
        tokens = arg.upper().split()
        # PostgreSQL identifies a function by its input arguments: OUT ones are not part of it.
        if tokens and tokens[0] == "OUT":
            continue
        if tokens and tokens[0] in {"IN", "INOUT", "VARIADIC"}:
            tokens = tokens[1:]
        if len(tokens) > 1 and tokens[0] not in MULTIWORD_TYPES:
            tokens = tokens[1:]
        name = " ".join(tokens)
        types.append(TYPE_ALIASES.get(name, name))
    return tuple(types)


def _object_key(kind: str, name: str, args: str | None) -> tuple:
    kind = " ".join(kind.upper().split())
    name = name.replace('"', "").lower()
    if "." not in name:
        name = "public." + name
    signature = _arg_types(args[1:-1]) if kind in {"FUNCTION", "PROCEDURE"} and args else None
    return (kind, name, signature)


def _parenthesised(code: str, start: int) -> str:
    """The `(…)` group opening at `code[start]`, nested groups and `'…'` literals included."""
    depth, end, quoted = 1, start + 1, False
    while end < len(code) and depth:
        c = code[end]
        if c == "'":
            quoted = not quoted
        elif not quoted:
            depth += {"(": 1, ")": -1}.get(c, 0)
        end += 1
    return code[start:end]


def _created_objects(code: str) -> list[tuple[int, tuple]]:
    """(offset, key) of every object a file creates; functions keep their argument types."""
    created = []
    for m in CREATE_OBJECT.finditer(code):
        kind, name, paren = m.group(1), m.group(2), m.group(3)
        args = _parenthesised(code, m.end() - 1) if paren else None
        created.append((m.start(), _object_key(kind, name, args)))
    return created


def _same_object(drop_key: tuple, key: tuple) -> bool:
    """A drop without an argument list names every overload of the function."""
    if drop_key[2] is None and drop_key[0] in {"FUNCTION", "PROCEDURE"}:
        return key[:2] == drop_key[:2]
    return key == drop_key


def _target(code: str, offset: int) -> str:
    """Table of the last `ALTER TABLE` before `offset`: column clauses are keyed on it."""
    last = None
    for m in ALTER_TABLE.finditer(code, 0, offset):
        last = m
    if last is None:
        return ""
    name = last.group(1).replace('"', "").lower()
    return name if "." in name else "public." + name


def destructive_statements(path: str, sql: str,
                           released_objects: set[tuple] | None = None) -> list[Finding]:
    """Every destructive statement of one SQL file, in file order.

    A drop is `exempt` when the file creates a function, procedure or view again afterwards
    with the same signature, or when `released_objects` is given and the object is not in it.
    """
    code = _blank_comments(sql)
    created = _created_objects(code)
    lines = sql.split("\n")
    hits: list[tuple[int, str, str]] = []
    for kind, pattern in DESTRUCTIVE:
        hits.extend((m.start(), kind, m.group(0)) for m in pattern.finditer(code))
    for m in ADD_COLUMN.finditer(code):
        if NOT_NULL.search(m.group(0)) and not HAS_VALUE.search(m.group(0)):
            hits.append((m.start(), "not null column without default", m.group(0)))
    findings = []
    for offset, kind, statement in sorted(hits):
        line_index = code.count("\n", 0, offset)
        exempt = False
        dropped = DROP_OBJECT.match(code, offset) if kind == "drop" else None
        if dropped and (dropped.group(2).endswith(".") or code.startswith("%", dropped.end(2))):
            # A `format()` template (`DROP TABLE public.%I`): a function dropping objects it
            # creates at run time, such as expired partitions, not a migration step.
            exempt = True
        elif dropped:
            args = _parenthesised(code, dropped.end() - 1) if dropped.group(3) else None
            key = _object_key(dropped.group(1), dropped.group(2), args)
            recreated = key[0] in RECREATABLE and any(
                o > offset and _same_object(key, k) for o, k in created)
            never_released = released_objects is not None and not any(
                _same_object(key, k) for k in released_objects)
            exempt = recreated or never_released
        findings.append(Finding(path, line_index + 1, kind, _normalise(statement),
                                _marker(lines, line_index), _target(code, offset),
                                _safe(lines, line_index), exempt, dropped is not None))
    return findings


def _version(tag: str) -> tuple[int, int, int] | None:
    m = SEMVER.match(tag)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None


def find_violations(current: dict[str, str], baseline: dict[str, str],
                    baseline_tag: str, released_tags: set[str]) -> list[str]:
    """Destructive statements new since the baseline that carry no valid marker.

    `current` and `baseline` map a file path to its SQL. A dropped object fails when the
    baseline has it, unless it is a function, procedure or view the file creates again with the
    same signature; any other destructive statement fails when the baseline tree does not
    already hold it on the same table. A `contract:` marker is valid when it names a released tag no newer than the
    baseline.
    """
    def forward(files: dict[str, str]):
        return [p for p in sorted(files) if p.endswith(".sql") and not p.endswith(".rollback.sql")]

    released_objects = {key for p in forward(baseline)
                        for _, key in _created_objects(_blank_comments(baseline[p]))}

    def scanned(files: dict[str, str], released: set[tuple] | None):
        for path in forward(files):
            yield from destructive_statements(path, files[path], released)

    # Column-level statements already in the baseline tree (in any file: release folders get
    # renamed) are not new. Dropped objects are judged on their own: the drop line of a
    # drop-and-recreate stays the same when the recreated signature changes.
    # Keyed on the table too: the same clause on another table is a new statement.
    remaining = Counter((f.target, f.statement) for f in scanned(baseline, None)
                        if not f.object_drop)
    baseline_version = _version(baseline_tag)
    errors = []
    for f in scanned(current, released_objects):
        if not f.object_drop and remaining[(f.target, f.statement)] > 0:
            remaining[(f.target, f.statement)] -= 1
            continue
        if f.exempt or f.safe:
            continue
        where = f"{f.path}:{f.line}: {f.kind}: {f.statement}"
        if f.marker is None:
            errors.append(f"{where}\n    an expand-only release must not drop, rename or tighten "
                          "what the previous release uses: move it to a later release with a "
                          "`-- contract: vX.Y.Z` marker, or justify it with `-- expand-safe: <why>`")
        elif f.marker not in released_tags:
            errors.append(f"{where}\n    contract marker {f.marker} is not a released tag")
        elif baseline_version is not None and _version(f.marker) > baseline_version:
            errors.append(f"{where}\n    contract marker {f.marker} is newer than the release in "
                          f"prod ({baseline_tag}): the expand step must be deployed first")
    return errors


def _git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], check=True,
                          capture_output=True, text=True).stdout


def _tree_at(root: Path, tag: str) -> dict[str, str]:
    files = {}
    for path in _git(root, "ls-tree", "-r", "--name-only", tag, "--", SQL_ROOT).splitlines():
        if path.endswith(".sql"):
            files[path] = _git(root, "show", f"{tag}:{path}")
    return files


def _working_tree(root: Path) -> dict[str, str]:
    return {str(p.relative_to(root)): p.read_text(encoding="utf-8")
            for p in sorted((root / SQL_ROOT).rglob("*.sql"))}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--baseline", required=True,
                        help="release deployed in prod, e.g. v3.4.0 (must be fetched)")
    parser.add_argument("--root", default=".", type=Path)
    args = parser.parse_args(argv)

    released = {t for t in _git(args.root, "tag", "--list", "v*").split() if _version(t)}
    errors = find_violations(_working_tree(args.root), _tree_at(args.root, args.baseline),
                             args.baseline, released)
    if errors:
        print(f"Expand/contract check against {args.baseline}: {len(errors)} violation(s)")
        for e in errors:
            print(f"  {e}")
        return 1
    print(f"Expand/contract check against {args.baseline}: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
