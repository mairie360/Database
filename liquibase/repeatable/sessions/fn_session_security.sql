-- Session checks and stolen-session reports shared by every API (MAIR-772, MAIR-773).
--
-- The API roles other than core_api have no access to `sessions` (it holds the hashes of the refresh tokens):
-- these SECURITY DEFINER functions return only what the JWT middleware of API_lib needs.

-- State of a session for the JWT middleware when its Redis key is missing (MAIR-772): whether the session is
-- active and belongs to this user, whose account is neither archived nor suspended, plus the address it was
-- opened or last seen from and the thumbprint of the device key it is bound to (NULL when not bound).
DROP FUNCTION IF EXISTS session_state(UUID, INT);
CREATE FUNCTION session_state(p_session_id UUID, p_user_id INT)
RETURNS TABLE (active BOOLEAN, ip_address INET, dpop_jkt TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT (s.revoked_at IS NULL
                AND (s.expires_at IS NULL OR s.expires_at > now())
                AND NOT u.is_archived
                AND u.status IS DISTINCT FROM 'suspended'),
           s.ip_address,
           s.dpop_jkt
    FROM sessions s
    JOIN users u ON u.id = s.user_id
    WHERE s.id = p_session_id AND s.user_id = p_user_id
$$;
REVOKE ALL ON FUNCTION session_state(UUID, INT) FROM PUBLIC;

-- Report of a suspicious use of a session (MAIR-773), in one transaction:
--   'certain'   the session is bound to a device and the request came without a valid proof: the session is
--               revoked, STOLEN_SESSION_ATTEMPT is logged and an alert is queued;
--   'possible'  the session is not bound and its address changed: same, with SUSPICIOUS_IP_CHANGE;
--   'ip_change' the bound device itself changed network: IP_CHANGE is logged and the address of the session
--               moves to the new one, nothing else.
-- One alert per session and level: a second report logs the attempt but queues nothing. A session already
-- revoked is logged without a new alert. NOTIFY session_security_alert carries the id of a new alert so Core
-- sends the e-mails at once (it also sweeps the unsent alerts). Returns
-- { known, revoked, alert_id } (alert_id NULL when nothing was queued); known = false when the session does
-- not exist or belongs to another user, in which case nothing is written.
DROP FUNCTION IF EXISTS report_suspicious_session_use(UUID, INT, TEXT, INET, TEXT);
CREATE FUNCTION report_suspicious_session_use(
    p_session_id UUID,
    p_user_id INT,
    p_level TEXT,
    p_ip_address INET,
    p_device_info TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_session sessions%ROWTYPE;
    v_action session_action;
    v_revoked BOOLEAN := FALSE;
    v_alert_id BIGINT;
    v_device TEXT := left(p_device_info, 512);
BEGIN
    IF p_level NOT IN ('certain', 'possible', 'ip_change') THEN
        RAISE EXCEPTION 'unknown level of a suspicious session use' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_session FROM sessions WHERE id = p_session_id AND user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('known', FALSE, 'revoked', FALSE, 'alert_id', NULL);
    END IF;

    v_action := CASE p_level
        WHEN 'certain' THEN 'STOLEN_SESSION_ATTEMPT'::session_action
        WHEN 'possible' THEN 'SUSPICIOUS_IP_CHANGE'::session_action
        ELSE 'IP_CHANGE'::session_action
    END;
    INSERT INTO connection_logs (user_id, session_id, ip_address, device_info, timestamp, action_type)
    VALUES (p_user_id, p_session_id, p_ip_address, v_device, now(), v_action);

    IF p_level = 'ip_change' THEN
        UPDATE sessions SET ip_address = p_ip_address WHERE id = p_session_id;
        RETURN jsonb_build_object('known', TRUE, 'revoked', FALSE, 'alert_id', NULL);
    END IF;

    IF v_session.revoked_at IS NULL THEN
        UPDATE sessions SET revoked_at = now() WHERE id = p_session_id;
        v_revoked := TRUE;
        INSERT INTO session_security_alerts (session_id, user_id, level, ip_address, device_info)
        VALUES (p_session_id, p_user_id, p_level, p_ip_address, v_device)
        ON CONFLICT (session_id, level) DO NOTHING
        RETURNING id INTO v_alert_id;
        IF v_alert_id IS NOT NULL THEN
            PERFORM pg_notify('session_security_alert', v_alert_id::TEXT);
        END IF;
    END IF;

    RETURN jsonb_build_object('known', TRUE, 'revoked', v_revoked, 'alert_id', v_alert_id);
END;
$$;
REVOKE ALL ON FUNCTION report_suspicious_session_use(UUID, INT, TEXT, INET, TEXT) FROM PUBLIC;
