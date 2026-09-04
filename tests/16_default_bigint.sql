BEGIN;
SELECT plan(1);

-- Test : S'assurer que chaque table a bien une clé primaire (avec cast explicite ::integer)
SELECT is(
    (
        SELECT count(*)::integer
        FROM information_schema.tables t
        WHERE t.table_schema = 'public'
          AND t.table_type = 'BASE TABLE'
          -- Tables techniques gérées par Liquibase (databasechangelog n'a pas de PK par design)
          AND t.table_name NOT IN ('databasechangelog', 'databasechangeloglock')
          AND NOT EXISTS (
              SELECT 1
              FROM information_schema.table_constraints tc
              WHERE tc.table_name = t.table_name
                AND tc.constraint_type = 'PRIMARY KEY'
          )
    ),
    0,
    'Performance Schema: Chaque table doit impérativement avoir une clé primaire définie.'
);

SELECT * FROM finish();
ROLLBACK;
