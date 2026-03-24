-- 1. Table de configuration
CREATE TABLE IF NOT EXISTS session_settings (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE,
    session_duration INTERVAL,
    CONSTRAINT one_row_only CHECK (id)
);

INSERT INTO session_settings (session_duration) 
VALUES ('7 days')
ON CONFLICT (id) DO NOTHING;

-- 2. Table des sessions (SANS la colonne générée)
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    device_info TEXT, 
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ, 
    revoked_at TIMESTAMPTZ
);

-- 3. La VUE pour ton Backend Rust
-- C'est cette "table virtuelle" que tu interrogeras dans ton code
CREATE OR REPLACE VIEW v_sessions AS
SELECT *,
    (revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())) AS is_active
FROM sessions;

-- 4. Index (indispensables pour la rapidité)
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_token_lookup ON sessions(token_hash);

-- 5. Ta fonction et ton trigger (inchangés)
CREATE OR REPLACE FUNCTION set_session_expiration()
RETURNS TRIGGER AS $$
DECLARE
    global_duration INTERVAL;
BEGIN
    SELECT session_duration INTO global_duration FROM session_settings LIMIT 1;
    IF NOT FOUND THEN
        global_duration := '30 days'::INTERVAL;
    END IF;

    IF global_duration IS NOT NULL THEN
        NEW.expires_at := NOW() + global_duration;
    ELSE
        NEW.expires_at := NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_expiration ON sessions;
CREATE TRIGGER trigger_set_expiration
BEFORE INSERT ON sessions
FOR EACH ROW EXECUTE FUNCTION set_session_expiration();