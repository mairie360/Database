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

-- Création du type ENUM (ajusté avec tes besoins)
DO $$ BEGIN
    CREATE TYPE session_action AS ENUM (
        'LOGIN', 
        'LOGOUT', 
        'REFRESH', 
        'EXPIRED',
        'CLEANUP'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Table des logs
CREATE TABLE IF NOT EXISTS connection_logs (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    ip_address INET,
    device_info TEXT,
    timestamp TIMESTAMPTZ DEFAULT now(),
    action_type session_action NOT NULL
);

-- Table de jointure
CREATE TABLE IF NOT EXISTS session_log_map (
    session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
    log_id INT REFERENCES connection_logs(id) ON DELETE CASCADE,
    PRIMARY KEY (session_id, log_id)
);

-- TRIGGER 1: LOGIN (Après insertion)
CREATE OR REPLACE FUNCTION log_session_start()
RETURNS TRIGGER AS $$
DECLARE
    v_log_id INT;
BEGIN
    INSERT INTO connection_logs (user_id, ip_address, device_info, timestamp, action_type)
    VALUES (NEW.user_id, NEW.ip_address, NEW.device_info, NEW.created_at, 'LOGIN')
    RETURNING id INTO v_log_id;

    INSERT INTO session_log_map (session_id, log_id)
    VALUES (NEW.id, v_log_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- TRIGGER 2: REFRESH (Après mise à jour du token)
CREATE OR REPLACE FUNCTION log_session_refresh()
RETURNS TRIGGER AS $$
DECLARE
    v_log_id INT;
BEGIN
    -- On logue le refresh (potentiellement avec une nouvelle IP/Device)
    INSERT INTO connection_logs (user_id, ip_address, device_info, timestamp, action_type)
    VALUES (NEW.user_id, NEW.ip_address, NEW.device_info, now(), 'REFRESH')
    RETURNING id INTO v_log_id;

    INSERT INTO session_log_map (session_id, log_id)
    VALUES (NEW.id, v_log_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- TRIGGER 3: END / CLEANUP (Avant suppression)
CREATE OR REPLACE FUNCTION log_session_end()
RETURNS TRIGGER AS $$
DECLARE
    v_action session_action;
BEGIN
    -- Détermination de la raison de la fin de session
    v_action := CASE 
        WHEN OLD.revoked_at IS NOT NULL THEN 'LOGOUT'::session_action
        WHEN OLD.expires_at < now() THEN 'EXPIRED'::session_action
        ELSE 'CLEANUP'::session_action
    END;

    INSERT INTO connection_logs (user_id, ip_address, device_info, timestamp, action_type)
    VALUES (OLD.user_id, OLD.ip_address, OLD.device_info, now(), v_action);
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Liaison Login
DROP TRIGGER IF EXISTS trigger_log_login ON sessions;
CREATE TRIGGER trigger_log_login
AFTER INSERT ON sessions
FOR EACH ROW EXECUTE FUNCTION log_session_start();

-- Liaison Refresh
DROP TRIGGER IF EXISTS trigger_log_refresh ON sessions;
CREATE TRIGGER trigger_log_refresh
AFTER UPDATE OF token_hash ON sessions
FOR EACH ROW EXECUTE FUNCTION log_session_refresh();

-- Liaison End
DROP TRIGGER IF EXISTS trigger_log_cleanup ON sessions;
CREATE TRIGGER trigger_log_cleanup
BEFORE DELETE ON sessions
FOR EACH ROW EXECUTE FUNCTION log_session_end();