-- Function (job title) of an agent, shown and edited on the Profile tab of Settings next to the
-- biography. Expand only: a nullable column of at most 100 characters (the API's limit) that must
-- hold a visible character (a value made of spaces, tabs or line breaks only is refused). Cleared
-- by anonymize_user() like the other identity columns.
ALTER TABLE users ADD COLUMN IF NOT EXISTS job_title VARCHAR(100);
ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_job_title;
ALTER TABLE users ADD CONSTRAINT chk_users_job_title CHECK (job_title IS NULL OR job_title ~ '[^[:space:]]');
