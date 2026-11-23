DROP INDEX IF EXISTS idx_user_courses_last_activity;
ALTER TABLE user_courses DROP COLUMN IF EXISTS last_activity_at;
