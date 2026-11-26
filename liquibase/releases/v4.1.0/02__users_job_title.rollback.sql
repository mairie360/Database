-- The column itself stays: v_users_active and v_users_archived select users.*, so a database
-- whose views were created after it depends on it, and the views are only re-created when their
-- file changes. The job titles are removed, since the code of the previous release does not clear
-- them at erasure.
ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_job_title;
UPDATE users SET job_title = NULL WHERE job_title IS NOT NULL;
