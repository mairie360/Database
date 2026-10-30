-- MAIR-524: GET /tasks of Project_API, the active tasks visible to the caller across every
-- project, ordered by due date. Partial indexes: archived (completed) tasks are never listed.
-- Pending tasks of one assignee (the dashboard), in one index range.
CREATE INDEX IF NOT EXISTS idx_tasks_assignee_due
    ON tasks (assigned_to, due_date, id) WHERE archived_at IS NULL;

-- Same list without assignee filter (Admin/Maire, Responsable).
CREATE INDEX IF NOT EXISTS idx_tasks_active_due
    ON tasks (due_date, id) WHERE archived_at IS NULL;
