-- MAIR-502: a completed task is archived. `archived_at` is set by the trigger of
-- repeatable/project/fn_set_task_archived_at.sql when the task becomes `completed` and
-- cleared when it is reopened. The project detail and the task list of Project_API only
-- read the active tasks (archived_at IS NULL), the archived ones have their own list.
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP;

-- The tasks already completed are archived as of their last update.
UPDATE tasks
SET archived_at = COALESCE(updated_at, created_at, CURRENT_TIMESTAMP)
WHERE status = 'completed' AND archived_at IS NULL;

-- Active tasks of a project, in the order of Project_API's lists (created_at, id).
CREATE INDEX IF NOT EXISTS idx_tasks_project_active
    ON tasks (project_id, created_at, id) WHERE archived_at IS NULL;
-- Archived tasks of a project, the most recently archived first.
CREATE INDEX IF NOT EXISTS idx_tasks_project_archived
    ON tasks (project_id, archived_at DESC, id DESC) WHERE archived_at IS NOT NULL;
