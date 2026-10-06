-- Static schema lint (rules adapted from Supabase splinter / pglinter).
-- Report mode: one row per finding. Run on a freshly migrated database.
WITH
fk_unindexed AS (
  SELECT 'unindexed_fk' AS rule, c.conrelid::regclass::text AS object, c.conname AS detail
  FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
  WHERE c.contype = 'f' AND n.nspname = 'public'
    AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = c.conrelid
                    AND (i.indkey::int2[])[0:array_length(c.conkey,1)-1] = c.conkey)
),
dup_idx AS (
  SELECT 'duplicate_index', a.indrelid::regclass::text,
         a.indexrelid::regclass || ' = ' || b.indexrelid::regclass
  FROM pg_index a JOIN pg_index b
    ON a.indrelid = b.indrelid AND a.indexrelid < b.indexrelid
   AND a.indkey = b.indkey AND a.indclass = b.indclass
   AND coalesce(pg_get_expr(a.indexprs, a.indrelid),'') = coalesce(pg_get_expr(b.indexprs, b.indrelid),'')
   AND coalesce(pg_get_expr(a.indpred, a.indrelid),'') = coalesce(pg_get_expr(b.indpred, b.indrelid),'')
  WHERE a.indrelid::regclass::text NOT LIKE 'pg_%'
),
prefix_idx AS (
  -- non-unique index whose columns are a strict prefix of another index
  SELECT 'redundant_prefix_index', a.indrelid::regclass::text,
         a.indexrelid::regclass || ' ⊂ ' || b.indexrelid::regclass
  FROM pg_index a JOIN pg_index b
    ON a.indrelid = b.indrelid AND a.indexrelid <> b.indexrelid
   AND NOT a.indisunique AND a.indpred IS NULL AND b.indpred IS NULL
   AND a.indexprs IS NULL AND b.indexprs IS NULL
   AND array_length(a.indkey::int2[],1) < array_length(b.indkey::int2[],1)
   AND (b.indkey::int2[])[0:array_length(a.indkey::int2[],1)-1] = (a.indkey::int2[])[:]
  JOIN pg_class t ON t.oid = a.indrelid JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'public'
),
no_pk AS (
  SELECT 'no_primary_key', c.oid::regclass::text, ''
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition
    AND c.relname NOT LIKE 'databasechangelog%'
    AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = c.oid AND contype = 'p')
),
bad_types AS (
  SELECT 'discouraged_type', (table_name||'.'||column_name), data_type
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND (data_type IN ('character', 'money', 'json', 'timestamp without time zone')
)
    AND table_name NOT LIKE 'databasechangelog%'
    AND table_name IN (SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                       WHERE n.nspname='public' AND c.relkind IN ('r','p') AND NOT c.relispartition)
),
int_pk AS (
  SELECT 'int4_primary_key', c.conrelid::regclass::text, a.attname
  FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
  JOIN pg_namespace n ON n.oid = c.connamespace
  JOIN pg_class t ON t.oid = c.conrelid
  WHERE c.contype='p' AND n.nspname='public' AND a.atttypid IN ('int4'::regtype,'int2'::regtype)
    AND array_length(c.conkey,1) = 1 AND NOT t.relispartition AND t.relname NOT LIKE 'databasechangelog%'
),
fk_type_mismatch AS (
  SELECT 'fk_type_mismatch', c.conrelid::regclass||'.'||a.attname,
         format_type(a.atttypid,a.atttypmod)||' -> '||c.confrelid::regclass||'.'||af.attname||' '||format_type(af.atttypid,af.atttypmod)
  FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
  CROSS JOIN LATERAL unnest(c.conkey, c.confkey) AS k(src, dst)
  JOIN pg_attribute a  ON a.attrelid=c.conrelid  AND a.attnum=k.src
  JOIN pg_attribute af ON af.attrelid=c.confrelid AND af.attnum=k.dst
  WHERE c.contype='f' AND n.nspname='public' AND a.atttypid <> af.atttypid
),
dup_trigger AS (
  -- two triggers on the same table, same timing/events, whose functions have the same body
  SELECT 'duplicate_trigger', a.tgrelid::regclass::text, a.tgname || ' ~ ' || b.tgname
  FROM pg_trigger a JOIN pg_trigger b
    ON a.tgrelid = b.tgrelid AND a.tgtype = b.tgtype AND a.oid < b.oid
  JOIN pg_proc pa ON pa.oid = a.tgfoid JOIN pg_proc pb ON pb.oid = b.tgfoid
  WHERE NOT a.tgisinternal AND NOT b.tgisinternal
    AND regexp_replace(replace(pa.prosrc, ':=', '='), '\s', '', 'g')
      = regexp_replace(replace(pb.prosrc, ':=', '='), '\s', '', 'g')
),
security_definer_no_path AS (
  SELECT 'security_definer_without_search_path', p.oid::regprocedure::text, ''
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef
    AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}')) cfg WHERE cfg LIKE 'search_path=%')
)
SELECT * FROM fk_unindexed UNION ALL SELECT * FROM dup_idx UNION ALL SELECT * FROM prefix_idx
UNION ALL SELECT * FROM no_pk UNION ALL SELECT * FROM bad_types UNION ALL SELECT * FROM int_pk
UNION ALL SELECT * FROM fk_type_mismatch UNION ALL SELECT * FROM security_definer_no_path UNION ALL SELECT * FROM dup_trigger
ORDER BY 1, 2, 3;
