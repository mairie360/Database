CREATE OR REPLACE FUNCTION fn_log_logout_on_revocation()
RETURNS TRIGGER AS $$
BEGIN
    -- On vérifie si la colonne revoked_at a été modifiée (et n'est plus NULL)
    IF (OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL) THEN
        INSERT INTO connection_logs (
            user_id,
            session_id,
            ip_address,
            device_info,
            timestamp,
            action_type
        ) VALUES (
            NEW.user_id,
            NEW.id,
            NEW.ip_address,
            NEW.device_info,
            NEW.revoked_at, -- On utilise la date de révocation
            'LOGOUT'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_log_logout_on_revocation ON sessions;

CREATE TRIGGER tr_log_logout_on_revocation
    AFTER UPDATE OF revoked_at ON sessions
    FOR EACH ROW
    WHEN (NEW.revoked_at IS NOT NULL)
    EXECUTE FUNCTION fn_log_logout_on_revocation();
