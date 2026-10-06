-- Project_API tasks/patch_task/view.rs: status change (trigger writes task_history)
\set uid random_exponential(2, 20000, 3)
SELECT EXISTS(SELECT 1 FROM users WHERE id = :uid AND NOT COALESCE(is_archived, false)) AS is_user_active;
\set tid random(1, 100000)
SELECT project_id AS pid FROM tasks WHERE id = :tid \gset
WITH updated AS (
  UPDATE tasks SET
    status = COALESCE(NULLIF('in_progress', '')::task_status, status),
    updated_by = :uid, updated_at = CURRENT_TIMESTAMP
  WHERE id = :tid AND project_id = :pid
  RETURNING id)
SELECT EXISTS (SELECT 1 FROM updated);
