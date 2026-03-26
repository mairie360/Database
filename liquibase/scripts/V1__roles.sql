-- 1. Table des rôles
CREATE TABLE IF NOT EXISTS roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    can_be_deleted BOOLEAN DEFAULT TRUE
);

-- Insertion des rôles de base
INSERT INTO roles (name, description, can_be_deleted) 
VALUES 
    ('Admin', 'Administrateur système', FALSE),
    ('User', 'Utilisateur standard', FALSE),
    ('Guest', 'Invité', FALSE)
ON CONFLICT (name) DO NOTHING;

-- 2. Table de jointure (Correction pour FK partitionnée)
CREATE TABLE IF NOT EXISTS user_roles (
    user_id INT NOT NULL,
    user_is_archived BOOLEAN NOT NULL DEFAULT FALSE CHECK (user_is_archived = FALSE),
    role_id INT NOT NULL,
    PRIMARY KEY (user_id, role_id),
    -- On pointe vers la clé composite (id, is_archived) de la table users
    CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id, user_is_archived) 
        REFERENCES users(id, is_archived) ON DELETE CASCADE,
    CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id) 
        REFERENCES roles(id) ON DELETE CASCADE
);

-- 3. Indexation
CREATE INDEX IF NOT EXISTS idx_user_roles_user ON user_roles(user_id, user_is_archived);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON user_roles(role_id);

-- 4. Attribution du rôle Admin à l'utilisateur ID 1 (si existant)
-- Utilisation d'un bloc DO pour éviter l'erreur si l'user 1 n'est pas encore créé
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE id = 1) THEN
        INSERT INTO user_roles (user_id, user_is_archived, role_id) 
        VALUES (1, FALSE, (SELECT id FROM roles WHERE name = 'Admin'))
        ON CONFLICT DO NOTHING;
    END IF;
END $$;

---
-- TRIGGERS DE SÉCURITÉ
---

-- Mise à jour du timestamp updated_at
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_roles_modtime
    BEFORE UPDATE ON roles
    FOR EACH ROW
    EXECUTE PROCEDURE update_modified_column();

-- Protection des rôles systèmes (Suppression)
CREATE OR REPLACE FUNCTION protect_critical_roles()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.can_be_deleted = FALSE THEN
        RAISE EXCEPTION 'Suppression impossible : le rôle "%" est critique pour le système.', OLD.name;
    END IF;
    RETURN OLD;
END;
$$ language 'plpgsql';

CREATE TRIGGER trigger_protect_roles
    BEFORE DELETE ON roles
    FOR EACH ROW
    EXECUTE PROCEDURE protect_critical_roles();

-- Protection des noms de rôles systèmes (Modification)
CREATE OR REPLACE FUNCTION protect_role_names()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.can_be_deleted = FALSE AND NEW.name <> OLD.name THEN
        RAISE EXCEPTION 'Modification interdite : le nom du rôle "%" est réservé.', OLD.name;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER trigger_protect_role_names
    BEFORE UPDATE ON roles
    FOR EACH ROW
    EXECUTE PROCEDURE protect_role_names();