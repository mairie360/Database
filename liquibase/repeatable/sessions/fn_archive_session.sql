CREATE OR REPLACE FUNCTION fn_handle_session_deletion()
RETURNS TRIGGER AS $$
DECLARE
    v_logs JSONB;
BEGIN
    -- 1. Créer le log de CLEANUP
    -- On insère en utilisant OLD car OLD contient les données de la session supprimée
    INSERT INTO connection_logs (user_id, session_id, ip_address, device_info, timestamp, action_type)
    VALUES (OLD.user_id, OLD.id, OLD.ip_address, OLD.device_info, now(), 'CLEANUP');

    -- 2. Récupérer les logs (incluant celui qu'on vient d'insérer)
    SELECT jsonb_agg(to_jsonb(l))
    INTO v_logs
    FROM connection_logs l
    WHERE l.session_id = OLD.id;

    -- -- 3. Archiver
    -- INSERT INTO sessions_archive (
    --     id, user_id, token_hash, device_info, ip_address,
    --     created_at, expires_at, revoked_at, logs_snapshot
    -- ) VALUES (
    --     OLD.id, OLD.user_id, OLD.token_hash, OLD.device_info, OLD.ip_address,
    --     OLD.created_at, OLD.expires_at, OLD.revoked_at, v_logs
    -- );

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- On ne garde qu'un seul trigger
DROP TRIGGER IF EXISTS tr_handle_session_deletion ON sessions;
CREATE TRIGGER tr_handle_session_deletion
    BEFORE DELETE ON sessions
    FOR EACH ROW
    EXECUTE FUNCTION fn_handle_session_deletion();
