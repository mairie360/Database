-- MAIR-393: task description, comments and history out of tasks.custom_fields.
--
-- Until now Project_API dropped the task description (no column), stacked
-- comments and a client-declared history inside tasks.custom_fields
-- (`comments`, `history`), rewriting the whole row on every addition, and
-- task_history only knew status changes, without their author.
--
-- - tasks.description: persisted description (empty string when absent).
-- - tasks.updated_by: author of the last write. Project_API sets it on every
--   INSERT/UPDATE; fn_log_task_change() signs the history with it. NULL means
--   a system write (e.g. fn_archive_user() unassigning tasks).
-- - task_comments: one row per comment.
-- - task_history: gains `action` and `changes` and becomes the only history,
--   written by fn_log_task_change() (repeatable/project/) and never by a
--   client. `label` only carries the free text of migrated legacy entries.
--
-- The legacy `comments` / `history` arrays are moved into the tables, then
-- removed from custom_fields. Malformed legacy items are kept with safe
-- fallbacks (author NULL, current timestamp) instead of being dropped.

---
-- tasks
---
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS chk_tasks_description_length;
ALTER TABLE tasks ADD CONSTRAINT chk_tasks_description_length
    CHECK (char_length(description) <= 5000);

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS updated_by INTEGER;
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS fk_tasks_updated_by;
ALTER TABLE tasks ADD CONSTRAINT fk_tasks_updated_by
    FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_updated_by ON tasks (updated_by);

---
-- task_comments
---
CREATE TABLE IF NOT EXISTS task_comments (
    id         SERIAL PRIMARY KEY,
    task_id    INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    author_id  INTEGER REFERENCES users(id) ON DELETE SET NULL,
    message    TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_task_comments_message
        CHECK (btrim(message) <> '' AND char_length(message) <= 2000)
);

-- Newest first, paginated per task.
CREATE INDEX IF NOT EXISTS idx_task_comments_task_created
    ON task_comments (task_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_task_comments_author ON task_comments (author_id);

---
-- task_history
---
ALTER TABLE task_history ADD COLUMN IF NOT EXISTS action VARCHAR(32) NOT NULL DEFAULT 'status_changed';
ALTER TABLE task_history DROP CONSTRAINT IF EXISTS chk_task_history_action;
ALTER TABLE task_history ADD CONSTRAINT chk_task_history_action
    CHECK (action IN ('task_created', 'task_updated', 'status_changed'));
ALTER TABLE task_history ADD COLUMN IF NOT EXISTS changes JSONB;
ALTER TABLE task_history DROP CONSTRAINT IF EXISTS chk_task_history_changes;
ALTER TABLE task_history ADD CONSTRAINT chk_task_history_changes
    CHECK (changes IS NULL OR jsonb_typeof(changes) = 'object');
ALTER TABLE task_history ADD COLUMN IF NOT EXISTS label TEXT;
UPDATE task_history SET changed_at = CURRENT_TIMESTAMP WHERE changed_at IS NULL;
ALTER TABLE task_history ALTER COLUMN changed_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_task_history_task_changed
    ON task_history (task_id, changed_at DESC, id DESC);

---
-- Legacy custom_fields.comments / custom_fields.history
---
-- `user-<id>` → id of an existing user, NULL otherwise.
CREATE FUNCTION pg_temp.legacy_author(p_item JSONB) RETURNS INTEGER AS $$
    SELECT u.id FROM users u
    WHERE p_item->'author'->>'id' ~ '^user-[0-9]{1,9}$'
      AND u.id = substring(p_item->'author'->>'id' FROM 6)::INTEGER;
$$ LANGUAGE sql STABLE;

-- ISO 8601 `createdAt` → UTC timestamp, current time when missing or invalid.
CREATE FUNCTION pg_temp.legacy_created_at(p_item JSONB) RETURNS TIMESTAMP AS $$
BEGIN
    RETURN COALESCE((p_item->>'createdAt')::TIMESTAMPTZ AT TIME ZONE 'UTC', CURRENT_TIMESTAMP);
EXCEPTION WHEN others THEN
    RETURN CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql STABLE;

INSERT INTO task_comments (task_id, author_id, message, created_at)
SELECT t.id,
       pg_temp.legacy_author(c.item),
       left(btrim(c.item->>'message'), 2000),
       pg_temp.legacy_created_at(c.item)
FROM tasks t
CROSS JOIN LATERAL jsonb_array_elements(t.custom_fields->'comments') WITH ORDINALITY AS c(item, n)
WHERE jsonb_typeof(t.custom_fields->'comments') = 'array'
  AND jsonb_typeof(c.item) = 'object'
  AND btrim(COALESCE(c.item->>'message', '')) <> ''
ORDER BY t.id, c.n;

INSERT INTO task_history (task_id, changed_by, action, label, changes, changed_at)
SELECT t.id,
       pg_temp.legacy_author(h.item),
       CASE WHEN h.item->>'action' IN ('task_created', 'task_updated', 'status_changed')
            THEN h.item->>'action' ELSE 'task_updated' END,
       NULLIF(left(btrim(COALESCE(h.item->>'label', '')), 255), ''),
       CASE WHEN jsonb_typeof(h.item->'changes') = 'object' THEN h.item->'changes' END,
       pg_temp.legacy_created_at(h.item)
FROM tasks t
CROSS JOIN LATERAL jsonb_array_elements(t.custom_fields->'history') WITH ORDINALITY AS h(item, n)
WHERE jsonb_typeof(t.custom_fields->'history') = 'array'
  AND jsonb_typeof(h.item) = 'object'
ORDER BY t.id, h.n;

UPDATE tasks SET custom_fields = custom_fields - 'comments' - 'history'
WHERE custom_fields->'comments' IS NOT NULL OR custom_fields->'history' IS NOT NULL;
