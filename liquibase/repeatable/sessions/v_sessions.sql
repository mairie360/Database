CREATE OR REPLACE VIEW v_sessions AS
SELECT *,
    (revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())) AS is_active
FROM sessions;
