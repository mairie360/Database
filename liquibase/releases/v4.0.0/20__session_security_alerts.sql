-- Attempts to use a stolen session (MAIR-773, epic MAIR-804). Expand only.
--
-- Three new entries of the session log: STOLEN_SESSION_ATTEMPT (certain: the session is bound to its
-- device and the request came without a valid proof), SUSPICIOUS_IP_CHANGE (possible: the session is not
-- bound and its address changed) and IP_CHANGE (the bound device itself changed network, no alert).
-- Postgres cannot drop an enum value: the rollback leaves them, unused.
ALTER TYPE session_action ADD VALUE IF NOT EXISTS 'STOLEN_SESSION_ATTEMPT';
ALTER TYPE session_action ADD VALUE IF NOT EXISTS 'SUSPICIOUS_IP_CHANGE';
ALTER TYPE session_action ADD VALUE IF NOT EXISTS 'IP_CHANGE';

-- Thumbprint (RFC 7638, base64url SHA-256) of the device key a session is bound to (DPoP, RFC 9449):
-- NULL for a session opened without a device key (older browser, or before the binding).
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS dpop_jkt TEXT;
ALTER TABLE sessions ADD CONSTRAINT chk_sessions_dpop_jkt
    CHECK (dpop_jkt IS NULL OR dpop_jkt ~ '^[A-Za-z0-9_-]{43}$');

-- Alerts to send to the agent and the administrators, written by report_suspicious_session_use() and read by
-- Core_API, which sends the e-mails (sent_at, attempts, last_error without data) and lets the agent close the
-- message shown at the next sign-in (acknowledged_at). One alert per session and level: an attacker replaying
-- the token does not send a new e-mail at every request.
CREATE TABLE session_security_alerts (
    id BIGSERIAL PRIMARY KEY,
    session_id UUID NOT NULL,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    level TEXT NOT NULL CONSTRAINT chk_session_security_alerts_level CHECK (level IN ('certain', 'possible')),
    ip_address INET,
    device_info TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at TIMESTAMPTZ,
    attempts INT NOT NULL DEFAULT 0 CONSTRAINT chk_session_security_alerts_attempts CHECK (attempts >= 0),
    last_attempt_at TIMESTAMPTZ,
    last_error TEXT CONSTRAINT chk_session_security_alerts_last_error CHECK (char_length(last_error) <= 200),
    acknowledged_at TIMESTAMPTZ,
    CONSTRAINT uq_session_security_alerts_session_level UNIQUE (session_id, level)
);
CREATE INDEX idx_session_security_alerts_user_id ON session_security_alerts (user_id, created_at DESC);
CREATE INDEX idx_session_security_alerts_created_at ON session_security_alerts (created_at DESC);
CREATE INDEX idx_session_security_alerts_unsent ON session_security_alerts (id) WHERE sent_at IS NULL;
