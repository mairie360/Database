CREATE OR REPLACE FUNCTION fn_archive_session_on_delete()
RETURNS TRIGGER AS $$
DECLARE
    v_logs JSONB;
BEGIN
    -- 1. Récupérer tous les logs associés à cette session en un tableau JSON
    SELECT jsonb_agg(to_jsonb(l))
    INTO v_logs
    FROM connection_logs l
    JOIN session_log_map m ON l.id = m.log_id
    WHERE m.session_id = OLD.id;

    -- 2. Insérer dans l'archive avec le snapshot des logs
    INSERT INTO sessions_archive (
        id, user_id, token_hash, device_info, ip_address,
        created_at, expires_at, revoked_at, logs_snapshot
    ) VALUES (
        OLD.id, OLD.user_id, OLD.token_hash, OLD.device_info, OLD.ip_address,
        OLD.created_at, OLD.expires_at, OLD.revoked_at, v_logs
    );

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_archive_session ON sessions;

CREATE TRIGGER tr_archive_session
    BEFORE DELETE ON sessions
    FOR EACH ROW
    EXECUTE FUNCTION fn_archive_session_on_delete();
