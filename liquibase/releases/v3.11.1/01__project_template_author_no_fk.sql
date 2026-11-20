-- The author of a project template is a plain indexed reference, not a foreign key.
--
-- The test harness of every API (mairie360_api_lib) starts with TRUNCATE users ... CASCADE: a foreign
-- key from project_templates to users makes that statement empty the templates and their statuses,
-- so no project created in a test gets statuses. The author is only compared with the caller's id;
-- user ids are never reused, so an id left behind by a hard delete (users are archived in practice,
-- see anonymize_user.sql) matches nobody and the template stays an Admin's.
ALTER TABLE project_templates
    DROP CONSTRAINT IF EXISTS project_templates_created_by_fkey;
