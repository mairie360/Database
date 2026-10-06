BEGIN;
SELECT plan(7);

-- Static schema lint (rules adapted from Supabase splinter / pglinter).
-- Each test lists the offending objects on failure. Informational rules
-- (timestamp without time zone, int4 surrogate keys) live in bench/lint.sql.
--
-- Known findings, tolerated until they are dropped by a release (see the
-- ticket referenced below); remove them from these lists in that release.
-- Any new finding fails the suite.
-- Empty since releases/v1.11.0 (MAIR-477) dropped the findings of MAIR-476.
CREATE TEMP TABLE lint_known_redundant_indexes (name TEXT) ON COMMIT DROP;
CREATE TEMP TABLE lint_known_duplicate_triggers (name TEXT) ON COMMIT DROP;

SELECT is_empty(
    $$ SELECT a.indexrelid::regclass::text || ' = ' || b.indexrelid::regclass::text
       FROM pg_index a
       JOIN pg_index b ON a.indrelid = b.indrelid AND a.indexrelid < b.indexrelid
        AND a.indkey = b.indkey AND a.indclass = b.indclass
        AND coalesce(pg_get_expr(a.indexprs, a.indrelid), '') = coalesce(pg_get_expr(b.indexprs, b.indrelid), '')
        AND coalesce(pg_get_expr(a.indpred, a.indrelid), '') = coalesce(pg_get_expr(b.indpred, b.indrelid), '')
       JOIN pg_class t ON t.oid = a.indrelid
       JOIN pg_namespace n ON n.oid = t.relnamespace
       WHERE n.nspname = 'public'
         AND a.indexrelid::regclass::text NOT IN (SELECT name FROM lint_known_redundant_indexes)
         AND b.indexrelid::regclass::text NOT IN (SELECT name FROM lint_known_redundant_indexes) $$,
    'Lint: no duplicate indexes (same columns, opclass, expression and predicate)'
);

SELECT is_empty(
    $$ SELECT a.indexrelid::regclass::text || ' is a prefix of ' || b.indexrelid::regclass::text
       FROM pg_index a
       JOIN pg_index b ON a.indrelid = b.indrelid AND a.indexrelid <> b.indexrelid
        AND NOT a.indisunique AND a.indpred IS NULL AND b.indpred IS NULL
        AND a.indexprs IS NULL AND b.indexprs IS NULL
        AND array_length(a.indkey::int2[], 1) < array_length(b.indkey::int2[], 1)
        AND (b.indkey::int2[])[0:array_length(a.indkey::int2[], 1) - 1] = (a.indkey::int2[])[:]
       JOIN pg_class t ON t.oid = a.indrelid
       JOIN pg_namespace n ON n.oid = t.relnamespace
       WHERE n.nspname = 'public'
         AND a.indexrelid::regclass::text NOT IN (SELECT name FROM lint_known_redundant_indexes) $$,
    'Lint: no non-unique index made redundant by a wider index starting with the same columns'
);

SELECT is_empty(
    $$ SELECT c.conrelid::regclass::text || '.' || c.conname
       FROM pg_constraint c
       JOIN pg_namespace n ON n.oid = c.connamespace
       WHERE c.contype = 'f' AND n.nspname = 'public'
         AND NOT EXISTS (SELECT 1 FROM pg_index i
                         WHERE i.indrelid = c.conrelid
                           AND (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] = c.conkey) $$,
    'Lint: every foreign key is covered by an index starting with its columns'
);

SELECT is_empty(
    $$ SELECT c.conrelid::regclass::text || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
              || ' -> ' || c.confrelid::regclass::text || '.' || af.attname || ' ' || format_type(af.atttypid, af.atttypmod)
       FROM pg_constraint c
       JOIN pg_namespace n ON n.oid = c.connamespace
       CROSS JOIN LATERAL unnest(c.conkey, c.confkey) AS k(src, dst)
       JOIN pg_attribute a  ON a.attrelid = c.conrelid  AND a.attnum = k.src
       JOIN pg_attribute af ON af.attrelid = c.confrelid AND af.attnum = k.dst
       WHERE c.contype = 'f' AND n.nspname = 'public' AND a.atttypid <> af.atttypid $$,
    'Lint: foreign key columns have the same type as the referenced columns'
);

SELECT is_empty(
    $$ SELECT c.oid::regclass::text
       FROM pg_class c
       JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relispartition
         AND c.relname NOT LIKE 'databasechangelog%'
         AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = c.oid AND contype = 'p') $$,
    'Lint: every table has a primary key'
);

SELECT is_empty(
    $$ SELECT p.oid::regprocedure::text
       FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.prosecdef
         AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) cfg
                         WHERE cfg LIKE 'search_path=%') $$,
    'Lint: SECURITY DEFINER functions pin their search_path'
);

SELECT is_empty(
    $$ SELECT a.tgrelid::regclass::text || ': ' || a.tgname || ' ~ ' || b.tgname
       FROM pg_trigger a
       JOIN pg_trigger b ON a.tgrelid = b.tgrelid AND a.tgtype = b.tgtype AND a.oid < b.oid
       JOIN pg_proc pa ON pa.oid = a.tgfoid
       JOIN pg_proc pb ON pb.oid = b.tgfoid
       WHERE NOT a.tgisinternal AND NOT b.tgisinternal
         AND regexp_replace(replace(pa.prosrc, ':=', '='), '\s', '', 'g')
           = regexp_replace(replace(pb.prosrc, ':=', '='), '\s', '', 'g')
         AND a.tgname NOT IN (SELECT name FROM lint_known_duplicate_triggers)
         AND b.tgname NOT IN (SELECT name FROM lint_known_duplicate_triggers) $$,
    'Lint: no two triggers with the same timing and events run the same function body'
);

SELECT * FROM finish();
ROLLBACK;
