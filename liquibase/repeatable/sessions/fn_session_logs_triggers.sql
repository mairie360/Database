-- 1. Log de Login
CREATE OR REPLACE FUNCTION log_session_start() RETURNS TRIGGER AS $$
DECLARE v_log_id UUID;
BEGIN
    INSERT INTO connection_logs (user_id, session_id, ip_address, device_info, timestamp, action_type)
    VALUES (NEW.user_id, NEW.id, NEW.ip_address, NEW.device_info, NEW.created_at, 'LOGIN')
    RETURNING id INTO v_log_id;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_log_login ON sessions;
CREATE TRIGGER trigger_log_login
    AFTER INSERT ON sessions
    FOR EACH ROW EXECUTE FUNCTION log_session_start();

-- 2. Log de Refresh
CREATE OR REPLACE FUNCTION log_session_refresh() RETURNS TRIGGER AS $$
DECLARE v_log_id UUID;
BEGIN
    INSERT INTO connection_logs (user_id, session_id, ip_address, device_info, timestamp, action_type)
    VALUES (NEW.user_id, NEW.id, NEW.ip_address, NEW.device_info, now(), 'REFRESH')
    RETURNING id INTO v_log_id;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_log_refresh ON sessions;
CREATE TRIGGER trigger_log_refresh
    AFTER UPDATE OF token_hash ON sessions
    FOR EACH ROW EXECUTE FUNCTION log_session_refresh();

-- 3. Log de Logout
CREATE OR REPLACE FUNCTION log_session_end() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO connection_logs (user_id, session_id, ip_address, device_info, timestamp, action_type)
    VALUES (OLD.user_id, OLD.id, OLD.ip_address, OLD.device_info, now(), 'LOGOUT');
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_log_logout ON sessions;
CREATE TRIGGER trigger_log_logout
    AFTER UPDATE OF revoked_at ON sessions -- Trigger AFTER pour être sûr que la modif est faite
    FOR EACH ROW
    WHEN (NEW.revoked_at IS NOT NULL AND OLD.revoked_at IS NULL) -- Uniquement à la première révocation
    EXECUTE FUNCTION log_session_end();
