DROP INDEX IF EXISTS idx_sessions_previous_token_hash;
ALTER TABLE sessions DROP COLUMN IF EXISTS rotated_at, DROP COLUMN IF EXISTS previous_token_hash;
