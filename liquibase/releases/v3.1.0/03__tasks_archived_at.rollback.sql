DROP INDEX IF EXISTS idx_tasks_project_archived;
DROP INDEX IF EXISTS idx_tasks_project_active;
DROP TRIGGER IF EXISTS tr_before_task_archive ON tasks;
DROP FUNCTION IF EXISTS fn_set_task_archived_at();
ALTER TABLE tasks DROP COLUMN IF EXISTS archived_at;
