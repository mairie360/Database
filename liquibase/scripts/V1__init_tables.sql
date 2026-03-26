---
-- 1. STRUCTURE DES TABLES (SANS PARTITIONNEMENT POUR COMPATIBILITÉ FK)
---

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(64) NOT NULL,
    last_name VARCHAR(64) NOT NULL,
    email VARCHAR(320) NOT NULL,
    password VARCHAR(255) NOT NULL,
    phone_number VARCHAR(15),
    photo bytea,
    status VARCHAR(16) NOT NULL CHECK (status IN ('active', 'inactive', 'pending', 'offline', 'archived')) DEFAULT 'offline',
    is_archived BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT uq_users_identity UNIQUE (id, is_archived)
);

-- Performances : Index filtré pour simuler la rapidité d'une partition
CREATE INDEX idx_users_not_archived ON users (id) WHERE is_archived = FALSE;

-- Vues pour l'abstraction logique (ne change pas pour votre app)
CREATE OR REPLACE VIEW v_users_active AS 
SELECT * FROM users WHERE is_archived = FALSE;

CREATE OR REPLACE VIEW v_users_archived AS 
SELECT * FROM users WHERE is_archived = TRUE;

---
-- 2. SYSTÈME D'AUDIT
---

DO $$ BEGIN
    CREATE TYPE user_audit_action AS ENUM ('CREATE', 'UPDATE', 'ARCHIVE', 'RESTORE');
EXCEPTION WHEN duplicate_object THEN null; END $$;

CREATE TABLE IF NOT EXISTS users_audit_log (
    audit_id SERIAL PRIMARY KEY,
    user_id INT,
    action_type user_audit_action NOT NULL,
    action_date TIMESTAMPTZ DEFAULT now(),
    action_by INT, 
    previous_data JSONB,
    new_data JSONB,
    reason TEXT
);

---
-- 3. LOGIQUE DES TRIGGERS
---

CREATE OR REPLACE FUNCTION fn_refresh_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_audit_and_mutate_user()
RETURNS TRIGGER AS $$
DECLARE
    v_action user_audit_action;
    v_user_id INT;
BEGIN
    v_user_id := COALESCE(NULLIF(current_setting('myapp.current_user_id', true), ''), '0')::INT;

    IF (TG_OP = 'INSERT') THEN 
        v_action := 'CREATE';
    ELSIF (TG_OP = 'UPDATE') THEN
        IF (OLD.is_archived = FALSE AND NEW.is_archived = TRUE) THEN v_action := 'ARCHIVE';
        ELSIF (OLD.is_archived = TRUE AND NEW.is_archived = FALSE) THEN v_action := 'RESTORE';
        ELSE v_action := 'UPDATE';
        END IF;
    END IF;

    INSERT INTO users_audit_log (user_id, action_type, action_by, previous_data, new_data)
    VALUES (
        COALESCE(NEW.id, OLD.id),
        v_action,
        v_user_id,
        CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END,
        to_jsonb(NEW)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_soft_delete_user_from_view()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE users 
    SET is_archived = TRUE, 
        status = 'archived'
    WHERE id = OLD.id AND is_archived = FALSE;
    RETURN NULL; 
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_protect_audit_log() RETURNS TRIGGER AS $$
BEGIN RAISE EXCEPTION 'Interdit : Modification de l’audit impossible.'; END; $$ LANGUAGE plpgsql;

---
-- 4. ATTACHEMENT DES TRIGGERS
---

CREATE TRIGGER tr_10_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_refresh_updated_at();

CREATE TRIGGER tr_20_user_lifecycle_audit
    AFTER INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_audit_and_mutate_user();

CREATE TRIGGER tr_view_soft_delete
    INSTEAD OF DELETE ON v_users_active
    FOR EACH ROW EXECUTE FUNCTION fn_soft_delete_user_from_view();

CREATE TRIGGER tr_immutable_audit 
    BEFORE UPDATE OR DELETE ON users_audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_protect_audit_log();

---
-- 5. FONCTIONS UTILES
---

CREATE OR REPLACE FUNCTION restore_user(target_id INT) 
RETURNS VOID AS $$
BEGIN
    UPDATE users 
    SET is_archived = FALSE, 
        status = 'offline'
    WHERE id = target_id AND is_archived = TRUE;
END;
$$ LANGUAGE plpgsql;