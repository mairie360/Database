CREATE OR REPLACE FUNCTION set_session_expiration()
RETURNS TRIGGER AS $$
DECLARE
    v_duration INTERVAL;
BEGIN
    SELECT session_duration INTO v_duration FROM session_settings LIMIT 1;
    NEW.expires_at := NOW() + COALESCE(v_duration, '30 days'::INTERVAL);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_expiration ON sessions;
CREATE TRIGGER trigger_set_expiration
BEFORE INSERT ON sessions
FOR EACH ROW EXECUTE FUNCTION set_session_expiration();
