-- Every refresh token a session replaced, to detect the reuse of any of them. Expand only.
--
-- Until now only the hash replaced by the last rotation was kept (`sessions.previous_token_hash`, releases/v3.8.0/01):
-- a token replaced two rotations ago or more was refused without closing the session. Each rotation now keeps the hash
-- it replaces here (the hash only, never the token) until the session row goes (ON DELETE CASCADE: retention purge,
-- erasure of the user). `replaced_at` is the time of the replacement itself (`clock_timestamp()`, not the start of the
-- rotation's transaction), on the Postgres clock the grace window is read on.
-- `previous_token_hash` and `rotated_at` are no longer read by Core_API; they stay until a contract release drops them.
-- Postgres cannot drop an enum value: the rollback leaves REFRESH_REUSE, unused.
ALTER TYPE session_action ADD VALUE IF NOT EXISTS 'REFRESH_REUSE';

CREATE TABLE session_replaced_refresh_tokens (
    token_hash TEXT PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    replaced_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_session_replaced_refresh_tokens_session_id ON session_replaced_refresh_tokens (session_id);

-- The tokens already replaced by the last rotation of each session.
INSERT INTO session_replaced_refresh_tokens (token_hash, session_id, replaced_at)
SELECT previous_token_hash, id, coalesce(rotated_at, now())
FROM sessions
WHERE previous_token_hash IS NOT NULL
ON CONFLICT (token_hash) DO NOTHING;

-- Every change of `sessions.token_hash` (a rotation) keeps the replaced hash. SECURITY DEFINER: core_api rotates the
-- token but has no access to this table; it reads it through report_refresh_token_reuse() only.
CREATE OR REPLACE FUNCTION fn_keep_replaced_refresh_token() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO session_replaced_refresh_tokens (token_hash, session_id, replaced_at)
    VALUES (OLD.token_hash, NEW.id, clock_timestamp())
    ON CONFLICT (token_hash) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION fn_keep_replaced_refresh_token() FROM PUBLIC;

CREATE TRIGGER tr_keep_replaced_refresh_token
    AFTER UPDATE OF token_hash ON sessions
    FOR EACH ROW
    WHEN (OLD.token_hash IS NOT NULL AND OLD.token_hash IS DISTINCT FROM NEW.token_hash)
    EXECUTE FUNCTION fn_keep_replaced_refresh_token();
