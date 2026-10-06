-- MAIR-477: trigram indexes for the user searches of Core_API (`users/list_directory`,
-- `admin/list_users`), which match `ILIKE '%term%'` on every name column and on the e-mail, joined
-- by OR: without an index on every branch, Postgres scans the whole `users` table on each search.
--
-- The full names are indexed as `first_name || ' ' || last_name` (and the reverse order, which the
-- admin search also matches): `concat_ws` is not IMMUTABLE and cannot be indexed, so the APIs
-- build the full name with `||` (both columns are NOT NULL, same result).
--
-- No B-tree on (last_name, first_name, id) for the ORDER BY: measured on 10 000 users, it makes
-- the planner walk it for a broad search (511 matches: 22 ms instead of 1.2 ms with the trigram
-- indexes alone).
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_users_first_name_trgm
    ON users USING gin (first_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_users_last_name_trgm
    ON users USING gin (last_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_users_email_trgm
    ON users USING gin (email gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_users_first_last_name_trgm
    ON users USING gin ((first_name || ' ' || last_name) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_users_last_first_name_trgm
    ON users USING gin ((last_name || ' ' || first_name) gin_trgm_ops);
