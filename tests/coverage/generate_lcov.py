#!/usr/bin/env python3
"""Génère un rapport LCOV à partir du profiler plpgsql_check.

Interroge plpgsql_profiler_function_tb() pour chaque fonction PL/pgSQL du
schéma public, puis retrouve dans les sources liquibase/repeatable/**/*.sql
la ligne de départ du corps de chaque fonction (juste après "AS $$") pour
convertir les numéros de ligne relatifs au corps en numéros de ligne absolus
dans le fichier source.
"""

import csv
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path("/workspace")
REPEATABLE_DIR = REPO_ROOT / "liquibase" / "repeatable"
OUTPUT_PATH = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO_ROOT / "coverage" / "coverage.lcov"

FUNCTION_RE = re.compile(
    r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:"?[A-Za-z_][\w]*"?\.)?"?([A-Za-z_][\w]*)"?\s*\(',
    re.IGNORECASE,
)
BODY_START_RE = re.compile(r'AS\s*\$\$')


def line_of(text: str, pos: int) -> int:
    return text.count("\n", 0, pos) + 1


def build_function_map():
    """name -> (relative_path, body_start_line). Raises on duplicate names."""
    mapping = {}
    for path in sorted(REPEATABLE_DIR.rglob("*.sql")):
        text = path.read_text(encoding="utf-8")
        for m in FUNCTION_RE.finditer(text):
            name = m.group(1)
            body_match = BODY_START_RE.search(text, m.end())
            if not body_match:
                print(f"WARN: no 'AS $$' found after CREATE FUNCTION {name} in {path}", file=sys.stderr)
                continue
            # plpgsql_check numbers lineno=1 as the physical line containing "AS $$"
            # itself (empty after the $$), not the line after it.
            body_start_line = line_of(text, body_match.end())
            rel_path = path.relative_to(REPO_ROOT).as_posix()
            if name in mapping and mapping[name] != (rel_path, body_start_line):
                print(
                    f"WARN: duplicate function name '{name}' found in {rel_path} "
                    f"(previously {mapping[name]}) — coverage mapping may be wrong",
                    file=sys.stderr,
                )
            mapping[name] = (rel_path, body_start_line)
    return mapping


def fetch_profiler_rows():
    query = """
    SELECT n.nspname, p.proname, t.lineno,
           COALESCE((SELECT sum(x) FROM unnest(t.exec_stmts) x), 0) AS hits
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    CROSS JOIN LATERAL plpgsql_profiler_function_tb(p.oid) t
    WHERE l.lanname = 'plpgsql'
      AND n.nspname = 'public'
      -- exclut les fonctions internes des extensions (pgtap, plpgsql_check...)
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e'
      )
    ORDER BY n.nspname, p.proname, t.lineno;
    """
    result = subprocess.run(
        ["psql", "-h", "database", "-U", "postgres", "-d", "core", "-At", "-F,", "-c", query],
        capture_output=True, text=True, check=True,
    )
    rows = []
    for row in csv.reader(result.stdout.splitlines()):
        if not row or len(row) != 4:
            continue
        _schema, proname, lineno, hits = row
        rows.append((proname, int(lineno), int(hits)))
    return rows


def main():
    function_map = build_function_map()
    rows = fetch_profiler_rows()

    per_file = {}  # rel_path -> {abs_line: hits}
    unmapped = set()
    for proname, lineno, hits in rows:
        if proname not in function_map:
            unmapped.add(proname)
            continue
        rel_path, body_start_line = function_map[proname]
        abs_line = body_start_line + (lineno - 1)
        file_hits = per_file.setdefault(rel_path, {})
        file_hits[abs_line] = file_hits.get(abs_line, 0) + hits

    if unmapped:
        print(f"WARN: {len(unmapped)} profiled function(s) had no source match: {sorted(unmapped)}", file=sys.stderr)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8") as f:
        for rel_path in sorted(per_file):
            lines = per_file[rel_path]
            f.write(f"SF:{rel_path}\n")
            lines_found = 0
            lines_hit = 0
            for abs_line in sorted(lines):
                hits = lines[abs_line]
                lines_found += 1
                if hits > 0:
                    lines_hit += 1
                f.write(f"DA:{abs_line},{hits}\n")
            f.write(f"LF:{lines_found}\n")
            f.write(f"LH:{lines_hit}\n")
            f.write("end_of_record\n")

    total_functions = len(per_file)
    print(f"Coverage written to {OUTPUT_PATH} ({total_functions} source file(s) covered)")


if __name__ == "__main__":
    main()
