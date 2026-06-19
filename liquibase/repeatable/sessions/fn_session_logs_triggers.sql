-- 1. Log de Login
CREATE OR REPLACE FUNCTION log_session_start() RETURNS TRIGGER AS $$
DECLARE v_log_id INT;
BEGIN
    INSERT INTO connection_logs (user_id, ip_address, device_info, timestamp, action_type)
    VALUES (NEW.user_id, NEW.ip_address, NEW.device_info, NEW.created_at, 'LOGIN')
    RETURNING id INTO v_log_id;
    INSERT INTO session_log_map (session_id, log_id) VALUES (NEW.id, v_log_id);
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_log_login ON sessions;
CREATE TRIGGER trigger_log_login
    AFTER INSERT ON sessions
    FOR EACH ROW EXECUTE FUNCTION log_session_start();

-- 2. Log de Refresh
CREATE OR REPLACE FUNCTION log_session_refresh() RETURNS TRIGGER AS $$
DECLARE v_log_id INT;
BEGIN
    INSERT INTO connection_logs (user_id, ip_address, device_info, timestamp, action_type)
    VALUES (NEW.user_id, NEW.ip_address, NEW.device_info, now(), 'REFRESH')
    RETURNING id INTO v_log_id;
    INSERT INTO session_log_map (session_id, log_id) VALUES (NEW.id, v_log_id);
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_log_refresh ON sessions;
CREATE TRIGGER trigger_log_refresh
    AFTER UPDATE OF token_hash ON sessions
    FOR EACH ROW EXECUTE FUNCTION log_session_refresh();

-- 3. Log de Cleanup/Logout
CREATE OR REPLACE FUNCTION log_session_end() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO connection_logs (user_id, ip_address, device_info, timestamp, action_type)
    VALUES (
        OLD.user_id,
        OLD.ip_address,
        OLD.device_info,
        now(),
        CASE
            WHEN OLD.revoked_at IS NOT NULL THEN 'LOGOUT'::session_action
            WHEN OLD.expires_at < now() THEN 'EXPIRED'::session_action
            ELSE 'CLEANUP'::session_action
        END
    );
    RETURN OLD;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_log_cleanup ON sessions;
CREATE TRIGGER trigger_log_cleanup
    BEFORE DELETE ON sessions
    FOR EACH ROW EXECUTE FUNCTION log_session_end();
