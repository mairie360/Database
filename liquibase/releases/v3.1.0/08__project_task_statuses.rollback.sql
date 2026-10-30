-- The statuses of every project and the templates are lost; tasks keep their category
-- (tasks.status). Tasks moved from `review` to `in_progress` stay in progress.
DROP TRIGGER IF EXISTS tr_before_task_apply_status ON tasks;
DROP FUNCTION IF EXISTS fn_apply_task_status();
DROP TRIGGER IF EXISTS tr_before_project_template ON projects;
DROP TRIGGER IF EXISTS tr_after_project_copy_statuses ON projects;
DROP FUNCTION IF EXISTS fn_set_project_template();
DROP FUNCTION IF EXISTS fn_copy_template_statuses();
DROP TRIGGER IF EXISTS tr_check_project_status_categories ON project_task_statuses;
DROP TRIGGER IF EXISTS tr_check_template_status_categories ON project_template_statuses;
DROP TRIGGER IF EXISTS tr_after_project_status_category ON project_task_statuses;
DROP TRIGGER IF EXISTS tr_before_project_template_delete ON project_templates;
DROP FUNCTION IF EXISTS fn_check_status_categories();
DROP FUNCTION IF EXISTS fn_sync_status_category();
DROP FUNCTION IF EXISTS fn_protect_default_template();
ALTER TABLE tasks DROP COLUMN IF EXISTS status_id;
ALTER TABLE projects DROP COLUMN IF EXISTS template_id;
DROP TABLE IF EXISTS project_task_statuses;
DROP TABLE IF EXISTS project_template_statuses;
DROP TABLE IF EXISTS project_templates;
