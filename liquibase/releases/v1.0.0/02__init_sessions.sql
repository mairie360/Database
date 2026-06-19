---
-- 1. TABLE DE CONFIGURATION
---
CREATE TABLE IF NOT EXISTS session_settings (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE,
    session_duration INTERVAL,
    CONSTRAINT one_row_only CHECK (id)
);

INSERT INTO session_settings (session_duration)
VALUES ('7 days')
ON CONFLICT (id) DO NOTHING;

---
-- 2. TABLE DES SESSIONS
---
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- FK simple
    token_hash TEXT NOT NULL UNIQUE,
    device_info TEXT,
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ
);

---
-- 3. INDEX
---
CREATE INDEX IF NOT EXISTS idx_sessions_user_lookup ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_token_lookup ON sessions(token_hash);

---
-- 4. SYSTÈME DE LOGS DE CONNEXION (STRUCTURE)
---
DO $$ BEGIN
    CREATE TYPE session_action AS ENUM ('LOGIN', 'LOGOUT', 'REFRESH', 'EXPIRED', 'CLEANUP');
EXCEPTION WHEN duplicate_object THEN null; END $$;

CREATE TABLE IF NOT EXISTS connection_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- FK simple
    ip_address INET,
    device_info TEXT,
    timestamp TIMESTAMPTZ DEFAULT now(),
    action_type session_action NOT NULL
);

CREATE TABLE IF NOT EXISTS session_log_map (
    session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
    log_id UUID REFERENCES connection_logs(id) ON DELETE CASCADE,
    PRIMARY KEY (session_id, log_id)
);

-- CREATE TABLE IF NOT EXISTS sessions_archive (
--     id UUID PRIMARY KEY,
--     user_id INT,
--     token_hash TEXT,
--     device_info TEXT,
--     ip_address INET,
--     created_at TIMESTAMPTZ,
--     expires_at TIMESTAMPTZ,
--     revoked_at TIMESTAMPTZ,
--     archived_at TIMESTAMPTZ DEFAULT now(),
--     logs_snapshot JSONB  -- Contient tous les logs de la session
-- );
