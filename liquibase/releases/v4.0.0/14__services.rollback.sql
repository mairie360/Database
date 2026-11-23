DROP INDEX IF EXISTS idx_users_service_id;
ALTER TABLE users DROP COLUMN IF EXISTS service_id;
DROP TABLE IF EXISTS services;
