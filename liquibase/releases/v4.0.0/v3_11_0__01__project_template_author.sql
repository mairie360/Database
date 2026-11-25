-- Author of a project template. Project_API lets an Admin manage every template and a Responsable
-- only the templates they created (never the default one); without an author it cannot tell
-- whose template it is.
--
-- The author goes NULL when the user row is deleted (it is archived in practice, see
-- anonymize_user.sql): a template without author can only be managed by an Admin.
ALTER TABLE project_templates
    ADD COLUMN IF NOT EXISTS created_by INT REFERENCES users(id) ON DELETE SET NULL;

-- Every foreign key has an index (the lint of tests/30): the author is read on each modification.
CREATE INDEX IF NOT EXISTS idx_project_templates_created_by ON project_templates (created_by);

-- Existing templates (the four seeded ones and those written before this column) belong to the
-- system admin, users.id = 1. On a new database that account does not exist yet while the
-- changesets run: repeatable/common/create_admin.sql then does the same once it has seeded it.
UPDATE project_templates
SET created_by = 1
WHERE created_by IS NULL
  AND EXISTS (SELECT 1 FROM users WHERE id = 1);
