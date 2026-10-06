BEGIN;
SELECT plan(4);

-- Personal data inventory (MAIR-285): gdpr/inventory.yaml must classify every column of the
-- migrated schema, and nothing else. tests/gdpr/load_inventory.py loads it into gdpr.inventory
-- before pg_prove (docker-compose-test.yml). Each test lists the offending columns on failure.

SELECT has_table('gdpr', 'inventory', 'GDPR inventory: gdpr/inventory.yaml is loaded');

CREATE TEMP TABLE schema_columns ON COMMIT DROP AS
SELECT c.relname::text AS table_name, a.attname::text AS column_name
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relispartition;

SELECT is_empty(
    $$ SELECT table_name || '.' || column_name FROM schema_columns
       EXCEPT
       SELECT table_name || '.' || column_name FROM gdpr.inventory $$,
    'GDPR inventory: every column of the schema is classified in gdpr/inventory.yaml'
);

SELECT is_empty(
    $$ SELECT table_name || '.' || column_name FROM gdpr.inventory
       EXCEPT
       SELECT table_name || '.' || column_name FROM schema_columns $$,
    'GDPR inventory: every column of gdpr/inventory.yaml exists in the schema'
);

SELECT is_empty(
    $$ SELECT c.conrelid::regclass::text || '.' || a.attname
       FROM pg_constraint c
       JOIN pg_class t ON t.oid = c.conrelid
       JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
       LEFT JOIN gdpr.inventory i ON i.table_name = t.relname AND i.column_name = a.attname
       WHERE c.contype = 'f' AND c.confrelid = 'public.users'::regclass AND NOT t.relispartition
         AND (i.category IS DISTINCT FROM 'identifier') $$,
    'GDPR inventory: every column that references users is a personal identifier'
);

SELECT * FROM finish();
ROLLBACK;
