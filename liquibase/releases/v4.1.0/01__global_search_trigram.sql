-- Trigram indexes of the global search (GET /v1/search of each business API): every API matches
-- `<column> ILIKE '%term%'` on the columns below. Without a trigram index, Postgres scans the whole
-- table on each search. `pg_trgm` is already installed (releases/v3.0.0).
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_projects_title_trgm
    ON projects USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_projects_description_trgm
    ON projects USING gin (description gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_tasks_title_trgm
    ON tasks USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_events_name_trgm
    ON events USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_conversations_title_trgm
    ON conversations USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_messages_content_trgm
    ON messages USING gin (content gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_courses_title_trgm
    ON courses USING gin (title gin_trgm_ops);
