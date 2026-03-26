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
-- 2. TABLE DES SESSIONS (CORRIGÉE POUR LE PARTITIONNEMENT)
---
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INT NOT NULL,
    -- Requis pour pointer vers la PK de la table partitionnée 'users'
    user_is_archived BOOLEAN DEFAULT FALSE CHECK (user_is_archived = FALSE),
    token_hash TEXT NOT NULL UNIQUE,
    device_info TEXT, 
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ, 
    revoked_at TIMESTAMPTZ,
    -- La FK doit inclure la clé de partitionnement
    FOREIGN KEY (user_id, user_is_archived) REFERENCES users(id, is_archived) ON DELETE CASCADE
);

---
-- 3. VUE POUR LE BACKEND RUST
---
CREATE OR REPLACE VIEW v_sessions AS
SELECT *,
    (revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())) AS is_active
FROM sessions;

---
-- 4. INDEX
---
CREATE INDEX IF NOT EXISTS idx_sessions_user_lookup ON sessions(user_id, user_is_archived);
CREATE INDEX IF NOT EXISTS idx_sessions_token_lookup ON sessions(token_hash);

---
-- 5. LOGIQUE D'EXPIRATION
---
CREATE OR REPLACE FUNCTION set_session_expiration()
RETURNS TRIGGER AS $$
DECLARE
    v_duration INTERVAL;
BEGIN
    SELECT session_duration INTO v_duration FROM session_settings LIMIT 1;
    NEW.expires_at := NOW() + COALESCE(v_duration, '30 days'::INTERVAL);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_expiration ON sessions;
CREATE TRIGGER trigger_set_expiration
BEFORE INSERT ON sessions
FOR EACH ROW EXECUTE FUNCTION set_session_expiration();

CREATE OR REPLACE FUNCTION is_session_valid(p_token_hash TEXT, p_device_info TEXT)
RETURNS TABLE(valid BOOLEAN, user_id INT) AS $$
BEGIN
    RETURN QUERY
    SELECT TRUE, s.user_id
    FROM v_sessions s
    WHERE s.token_hash = p_token_hash
      AND s.is_active = TRUE
      AND (s.device_info = p_device_info OR s.device_info IS NULL)
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

---
-- 6. SYSTÈME DE LOGS DE CONNEXION
---
DO $$ BEGIN
    CREATE TYPE session_action AS ENUM ('LOGIN', 'LOGOUT', 'REFRESH', 'EXPIRED', 'CLEANUP');
EXCEPTION WHEN duplicate_object THEN null; END $$;

CREATE TABLE IF NOT EXISTS connection_logs (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    user_is_archived BOOLEAN NOT NULL,
    ip_address INET,
    device_info TEXT,
    timestamp TIMESTAMPTZ DEFAULT now(),
    action_type session_action NOT NULL,
    FOREIGN KEY (user_id, user_is_archived) REFERENCES users(id, is_archived) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS session_log_map (
    session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
    log_id INT REFERENCES connection_logs(id) ON DELETE CASCADE,
    PRIMARY KEY (session_id, log_id)
);

-- Fonctions de Trigger de Log
CREATE OR REPLACE FUNCTION log_session_start() RETURNS TRIGGER AS $$
DECLARE v_log_id INT;
BEGIN
    INSERT INTO connection_logs (user_id, user_is_archived, ip_address, device_info, timestamp, action_type)
    VALUES (NEW.user_id, NEW.user_is_archived, NEW.ip_address, NEW.device_info, NEW.created_at, 'LOGIN')
    RETURNING id INTO v_log_id;
    INSERT INTO session_log_map (session_id, log_id) VALUES (NEW.id, v_log_id);
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION log_session_refresh() RETURNS TRIGGER AS $$
DECLARE v_log_id INT;
BEGIN
    INSERT INTO connection_logs (user_id, user_is_archived, ip_address, device_info, timestamp, action_type)
    VALUES (NEW.user_id, NEW.user_is_archived, NEW.ip_address, NEW.device_info, now(), 'REFRESH')
    RETURNING id INTO v_log_id;
    INSERT INTO session_log_map (session_id, log_id) VALUES (NEW.id, v_log_id);
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION log_session_end() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO connection_logs (user_id, user_is_archived, ip_address, device_info, timestamp, action_type)
    VALUES (
        OLD.user_id, 
        OLD.user_is_archived, 
        OLD.ip_address, 
        OLD.device_info, 
        now(), 
        CASE 
            WHEN OLD.revoked_at IS NOT NULL THEN 'LOGOUT'::session_action
            WHEN OLD.expires_at < now() THEN 'EXPIRED'::session_action
            ELSE 'CLEANUP'::session_action
        END
    );
    RETURN OLD;
END; $$ LANGUAGE plpgsql;

-- Attachement des triggers
CREATE TRIGGER trigger_log_login AFTER INSERT ON sessions FOR EACH ROW EXECUTE FUNCTION log_session_start();
CREATE TRIGGER trigger_log_refresh AFTER UPDATE OF token_hash ON sessions FOR EACH ROW EXECUTE FUNCTION log_session_refresh();
CREATE TRIGGER trigger_log_cleanup BEFORE DELETE ON sessions FOR EACH ROW EXECUTE FUNCTION log_session_end();