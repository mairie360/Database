-- Reuse of a rotated refresh token.
--
-- Core_API rotates the refresh token of a session at each refresh. It now keeps the hash of the
-- token it replaced (`previous_token_hash`) and the time of that rotation (`rotated_at`), so a
-- refresh with that previous token can be told from an unknown one: within a short grace window
-- (concurrent refreshes of several fronts) Core only refuses it, later it revokes the session.
-- Both columns are NULL until the first rotation. The partial index serves Core's lookup by the
-- previous hash, which only runs for tokens that match no current hash.
ALTER TABLE sessions
    ADD COLUMN previous_token_hash TEXT,
    ADD COLUMN rotated_at TIMESTAMPTZ;
CREATE INDEX idx_sessions_previous_token_hash ON sessions (previous_token_hash)
    WHERE previous_token_hash IS NOT NULL;
