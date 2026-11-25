DROP INDEX IF EXISTS idx_project_templates_created_by;
ALTER TABLE project_templates DROP COLUMN IF EXISTS created_by;
