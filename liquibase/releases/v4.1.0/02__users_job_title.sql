-- Function (job title) of an agent, shown and edited on the Profile tab of Settings next to the
-- biography. Expand only: a nullable column; the length check matches the API's limit (100
-- characters). Cleared by anonymize_user() like the other identity columns.
ALTER TABLE users ADD COLUMN IF NOT EXISTS job_title VARCHAR(100);
ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_job_title;
ALTER TABLE users ADD CONSTRAINT chk_users_job_title CHECK (job_title IS NULL OR length(btrim(job_title)) BETWEEN 1 AND 100);
