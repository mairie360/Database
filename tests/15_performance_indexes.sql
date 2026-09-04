BEGIN;
SELECT plan(1);

-- Test : Vérifier qu'il n'y a aucune clé étrangère sans index (avec cast explicite ::integer)
SELECT is(
    (
        SELECT count(*)::integer
        FROM (
            SELECT
                conrelid::regclass AS table_name,
                conname AS constraint_name
            FROM pg_constraint c
            JOIN pg_namespace n ON n.oid = c.connamespace
            WHERE c.contype = 'f'
              AND n.nspname = 'public'
              AND NOT EXISTS (
                  SELECT 1
                  FROM pg_index i
                  WHERE i.indrelid = c.conrelid
                    AND i.indkey[0:array_length(c.conkey,1)-1] = c.conkey
              )
        ) unindexed_fks
    ),
    0,
    'Performance Schema: Toutes les clés étrangères doivent posséder un index pour éviter les sequential scans.'
);

SELECT * FROM finish();
ROLLBACK;
