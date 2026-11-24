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

-- Report of a refresh token presented again after a rotation replaced it, in one transaction. Called by
-- Core_API only when the token matches no current token of a session:
--   unknown hash                     nothing is written, known = false;
--   replaced less than p_grace_seconds ago
--                                    a concurrent renewal of the same session by another front: nothing is written,
--                                    superseded = true while the session is still active (the caller lets the front
--                                    read the cookie the other renewal set), false when the session already ended;
--   replaced longer ago              two parties hold the session's tokens (a stolen token replayed, or the thief
--                                    already renewed): REFRESH_REUSE is logged with the address and the device; an
--                                    active session is revoked and one 'certain' alert is queued (same circuit as
--                                    report_suspicious_session_use(): the agent and the administrators are e-mailed).
-- Returns { known, superseded, reused, revoked, session_id, user_id, alert_id }.
DROP FUNCTION IF EXISTS report_refresh_token_reuse(TEXT, INT, INET, TEXT);
CREATE FUNCTION report_refresh_token_reuse(
    p_token_hash TEXT,
    p_grace_seconds INT,
    p_ip_address INET,
    p_device_info TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_replaced session_replaced_refresh_tokens%ROWTYPE;
    v_session sessions%ROWTYPE;
    v_active BOOLEAN;
    v_now TIMESTAMPTZ;
    v_alert_id BIGINT;
    v_device TEXT := left(p_device_info, 512);
BEGIN
    IF p_grace_seconds IS NULL OR p_grace_seconds < 0 THEN
        RAISE EXCEPTION 'the grace window of a replaced refresh token cannot be negative' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_replaced FROM session_replaced_refresh_tokens WHERE token_hash = p_token_hash;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('known', FALSE, 'superseded', FALSE, 'reused', FALSE, 'revoked', FALSE,
                                  'session_id', NULL, 'user_id', NULL, 'alert_id', NULL);
    END IF;

    -- Locked: a rotation of the same session running at the same time waits.
    SELECT * INTO v_session FROM sessions WHERE id = v_replaced.session_id FOR UPDATE;
    IF NOT FOUND THEN
        -- The session was deleted between the two reads: its tokens are unknown now.
        RETURN jsonb_build_object('known', FALSE, 'superseded', FALSE, 'reused', FALSE, 'revoked', FALSE,
                                  'session_id', NULL, 'user_id', NULL, 'alert_id', NULL);
    END IF;
    -- Read after the lock, not at the start of the transaction: a wait on the lock must not stretch the window.
    v_now := clock_timestamp();
    v_active := v_session.revoked_at IS NULL AND (v_session.expires_at IS NULL OR v_session.expires_at > v_now);

    IF v_replaced.replaced_at > v_now - make_interval(secs => p_grace_seconds) THEN
        RETURN jsonb_build_object('known', TRUE, 'superseded', v_active, 'reused', FALSE, 'revoked', FALSE,
                                  'session_id', v_session.id, 'user_id', v_session.user_id, 'alert_id', NULL);
    END IF;

    INSERT INTO connection_logs (user_id, session_id, ip_address, device_info, timestamp, action_type)
    VALUES (v_session.user_id, v_session.id, p_ip_address, v_device, now(), 'REFRESH_REUSE');

    IF v_active THEN
        UPDATE sessions SET revoked_at = now() WHERE id = v_session.id;
        INSERT INTO session_security_alerts (session_id, user_id, level, ip_address, device_info)
        VALUES (v_session.id, v_session.user_id, 'certain', p_ip_address, v_device)
        ON CONFLICT (session_id, level) DO NOTHING
        RETURNING id INTO v_alert_id;
        IF v_alert_id IS NOT NULL THEN
            PERFORM pg_notify('session_security_alert', v_alert_id::TEXT);
        END IF;
    END IF;

    RETURN jsonb_build_object('known', TRUE, 'superseded', FALSE, 'reused', TRUE, 'revoked', v_active,
                              'session_id', v_session.id, 'user_id', v_session.user_id, 'alert_id', v_alert_id);
END;
$$;
REVOKE ALL ON FUNCTION report_refresh_token_reuse(TEXT, INT, INET, TEXT) FROM PUBLIC;
