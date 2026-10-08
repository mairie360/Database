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
DROP INDEX IF EXISTS idx_users_search_text_trgm;
