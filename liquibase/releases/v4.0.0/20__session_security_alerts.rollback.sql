DROP TABLE IF EXISTS session_security_alerts;
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS chk_sessions_dpop_jkt;
ALTER TABLE sessions DROP COLUMN IF EXISTS dpop_jkt;
-- The session_action values STOLEN_SESSION_ATTEMPT, SUSPICIOUS_IP_CHANGE and IP_CHANGE stay: Postgres cannot
-- drop an enum value. Unused once the functions are gone.
