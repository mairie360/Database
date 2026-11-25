-- Authors left dangling by a hard delete while the constraint was absent are cleared first.
UPDATE project_templates
SET created_by = NULL
WHERE created_by IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM users WHERE users.id = project_templates.created_by);
ALTER TABLE project_templates
    ADD CONSTRAINT project_templates_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;
