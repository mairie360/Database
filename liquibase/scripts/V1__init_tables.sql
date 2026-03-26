-- On renomme la table brute pour la partitionner
CREATE TABLE users_raw (
    id SERIAL,
    first_name VARCHAR(64) NOT NULL,
    last_name VARCHAR(64) NOT NULL,
    email VARCHAR(320) NOT NULL, -- Note: l'unicité globale est complexe sur les partitions
    password VARCHAR(255) NOT NULL,
    phone_number VARCHAR(15),
    photo bytea,
    status VARCHAR(16) NOT NULL CHECK (status IN ('active', 'inactive', 'pending', 'offline', 'archived')) DEFAULT 'offline',
    is_archived BOOLEAN DEFAULT FALSE, -- Notre clé de partition
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (id, is_archived)
) PARTITION BY LIST (is_archived);

-- Création des segments physiques
CREATE TABLE users_active PARTITION OF users_raw FOR VALUES IN (FALSE);
CREATE TABLE users_archive PARTITION OF users_raw FOR VALUES IN (TRUE);

CREATE UNIQUE INDEX idx_users_active_email ON users_active (email);

CREATE VIEW users AS 
SELECT * FROM users_raw 
WHERE is_archived = FALSE;

-- Type d'action unifié
DO $$ BEGIN
    CREATE TYPE user_audit_action AS ENUM ('CREATE', 'UPDATE', 'ARCHIVE', 'RESTORE');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- Table d'audit (Immutable)
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

-- Trigger d'immuabilité pour l'audit
CREATE OR REPLACE FUNCTION protect_audit_log() RETURNS TRIGGER AS $$
BEGIN RAISE EXCEPTION 'Interdit : Modification de l’audit impossible.'; END; $$ LANGUAGE plpgsql;

CREATE TRIGGER tr_immutable_audit BEFORE UPDATE OR DELETE ON users_audit_log
FOR EACH ROW EXECUTE FUNCTION protect_audit_log();

CREATE OR REPLACE FUNCTION fn_audit_and_mutate_user()
RETURNS TRIGGER AS $$
DECLARE
    v_action user_audit_action;
BEGIN
    -- 1. Déterminer l'action
    IF (TG_OP = 'INSERT') THEN 
        v_action := 'CREATE';
    ELSIF (TG_OP = 'UPDATE') THEN
        IF (OLD.is_archived = FALSE AND NEW.is_archived = TRUE) THEN v_action := 'ARCHIVE';
        ELSIF (OLD.is_archived = TRUE AND NEW.is_archived = FALSE) THEN v_action := 'RESTORE';
        ELSE v_action := 'UPDATE';
        END IF;
    END IF;

    -- 2. Insérer le log
    INSERT INTO users_audit_log (user_id, action_type, action_by, previous_data, new_data)
    VALUES (
        COALESCE(NEW.id, OLD.id),
        v_action,
        current_setting('myapp.current_user_id', true)::INT,
        CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger sur la table physique pour ne rien rater
CREATE TRIGGER tr_user_lifecycle
AFTER INSERT OR UPDATE ON users_raw
FOR EACH ROW EXECUTE FUNCTION fn_audit_and_mutate_user();

CREATE OR REPLACE FUNCTION fn_soft_delete_user()
RETURNS TRIGGER AS $$
BEGIN
    -- On ne supprime pas, on bascule le flag sur la table brute
    UPDATE users_raw 
    SET is_archived = TRUE, 
        status = 'archived',
        updated_at = now()
    WHERE id = OLD.id;
    
    RETURN NULL; -- Annule la suppression réelle
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_view_soft_delete
INSTEAD OF DELETE ON users
FOR EACH ROW EXECUTE FUNCTION fn_soft_delete_user();

CREATE OR REPLACE FUNCTION restore_user(target_id INT, p_reason TEXT DEFAULT 'Restauration administrative') 
RETURNS VOID AS $$
BEGIN
    -- L'UPDATE ici déclenchera automatiquement le trigger d'audit tr_user_lifecycle
    UPDATE users_raw 
    SET is_archived = FALSE, 
        status = 'offline',
        updated_at = now()
    WHERE id = target_id AND is_archived = TRUE;
    
    -- On peut ajouter la raison manuellement si besoin dans l'audit (via une variable temporaire ou un UPDATE du dernier log)
END;
$$ LANGUAGE plpgsql;