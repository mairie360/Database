-- Rollback of 02__task_description_comments_history.sql (MAIR-393).
--
-- Comments and the non-status history go back to tasks.custom_fields, in the
-- shape the forward migration reads (`author.id` = `user-<id>`, ISO 8601
-- `createdAt`), so a later update migrates them again. tasks.description and
-- tasks.updated_by have no place in the previous schema and are lost.

-- The trigger reads the columns dropped below: put back the status-only one of
-- the previous release (a rollback is followed by the `update` of that release,
-- which replaces it with its own copy).
DROP TRIGGER IF EXISTS tr_after_task_change ON tasks;
DROP FUNCTION IF EXISTS fn_log_task_change();

CREATE OR REPLACE FUNCTION fn_log_task_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO task_history (task_id, old_status, new_status)
        VALUES (NEW.id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_after_task_status_update ON tasks;
CREATE TRIGGER tr_after_task_status_update AFTER UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION fn_log_task_status_change();

UPDATE tasks t
SET custom_fields = COALESCE(t.custom_fields, '{}'::JSONB) || jsonb_build_object('comments', c.items)
FROM (
    SELECT task_id,
           jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'message', message,
               'createdAt', to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'author', CASE WHEN author_id IS NOT NULL
                              THEN jsonb_build_object('id', 'user-' || author_id) END
           )) ORDER BY created_at, id) AS items
    FROM task_comments
    GROUP BY task_id
) c
WHERE c.task_id = t.id;

UPDATE tasks t
SET custom_fields = COALESCE(t.custom_fields, '{}'::JSONB) || jsonb_build_object('history', h.items)
FROM (
    SELECT task_id,
           jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'action', action,
               'label', label,
               'changes', changes,
               'createdAt', to_char(changed_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'author', CASE WHEN changed_by IS NOT NULL
                              THEN jsonb_build_object('id', 'user-' || changed_by) END
           )) ORDER BY changed_at, id) AS items
    FROM task_history
    WHERE action <> 'status_changed'
    GROUP BY task_id
) h
WHERE h.task_id = t.id;

DELETE FROM task_history WHERE action <> 'status_changed';

DROP TABLE IF EXISTS task_comments;

DROP INDEX IF EXISTS idx_task_history_task_changed;
ALTER TABLE task_history
    ALTER COLUMN changed_at DROP NOT NULL,
    DROP CONSTRAINT IF EXISTS chk_task_history_changes,
    DROP CONSTRAINT IF EXISTS chk_task_history_action,
    DROP COLUMN IF EXISTS label,
    DROP COLUMN IF EXISTS changes,
    DROP COLUMN IF EXISTS action;

DROP INDEX IF EXISTS idx_tasks_updated_by;
ALTER TABLE tasks
    DROP CONSTRAINT IF EXISTS fk_tasks_updated_by,
    DROP CONSTRAINT IF EXISTS chk_tasks_description_length,
    DROP COLUMN IF EXISTS updated_by,
    DROP COLUMN IF EXISTS description;
