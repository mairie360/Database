-- One normalized search expression per user for Core_API's searches (MAIR-477, measured by
-- the MAIR-474 load test).
--
-- The searches matched `ILIKE '%term%'` on five expressions (first name, last name, both full
-- name orders, e-mail) joined by OR, served by the five trigram indexes of releases/v3.0.0. On
-- 10 000 users a broad term (5 % of the accounts) still read the whole table, five ILIKE per
-- row: 14 to 74 ms per directory search, 21 to 35 ms per e-mail search, the main load of
-- Core_API's Postgres. One lowered expression and one LIKE: 0.7 to 3.9 ms, generic plans
-- included.
--
-- The fields are joined by chr(31) (unit separator), which a search cannot contain, so a term
-- never matches across two fields; both name orders are kept so that "dupont jean" finds
-- "Jean Dupont". Core_API writes the same expression:
--   lower(first_name || ' ' || last_name || chr(31) || last_name || ' ' || first_name
--         || chr(31) || email) LIKE '%' || lower($1) || '%'
-- An expression index rather than a generated column: v_users_active and v_users_archived
-- select `users.*`, a new column would end up in them and could not be dropped back.
CREATE INDEX IF NOT EXISTS idx_users_search_text_trgm ON users USING gin (
    (lower(first_name || ' ' || last_name || chr(31)
           || last_name || ' ' || first_name || chr(31)
           || email)) gin_trgm_ops
);

-- The five indexes of releases/v3.0.0 served the former OR, no search uses them any more.
DROP INDEX IF EXISTS idx_users_first_name_trgm;
DROP INDEX IF EXISTS idx_users_last_name_trgm;
DROP INDEX IF EXISTS idx_users_email_trgm;
DROP INDEX IF EXISTS idx_users_first_last_name_trgm;
DROP INDEX IF EXISTS idx_users_last_first_name_trgm;
