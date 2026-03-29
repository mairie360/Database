CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    can_be_deleted BOOLEAN DEFAULT TRUE
);

INSERT INTO roles (name, description, can_be_deleted) VALUES
    ('Admin', 'Admin of the system', FALSE);

INSERT INTO roles (name, description, can_be_deleted) VALUES
    ('User', 'Basic user of the system', FALSE);

INSERT INTO roles (name, description, can_be_deleted) VALUES
    ('Guest', 'Guest user', FALSE);

CREATE TABLE user_roles (
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    role_id INT REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

CREATE INDEX idx_user_roles_user_id ON user_roles(user_id);
CREATE INDEX idx_user_roles_role_id ON user_roles(role_id);

INSERT INTO user_roles (user_id, role_id) VALUES
    (1, 1);

-- 1. On crée la fonction
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 2. On l'attache à la table roles
CREATE TRIGGER update_roles_modtime
    BEFORE UPDATE ON roles
    FOR EACH ROW
    EXECUTE PROCEDURE update_modified_column();
    
-- 1. Création de la fonction de vérification
CREATE OR REPLACE FUNCTION protect_critical_roles()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.can_be_deleted = FALSE THEN
        RAISE EXCEPTION 'Suppression impossible : le rôle "%" est marqué comme critique pour le système.', OLD.name;
    END IF;
    RETURN OLD;
END;
$$ language 'plpgsql';

-- 2. Attachement du trigger à la table roles
CREATE TRIGGER trigger_protect_roles
    BEFORE DELETE ON roles
    FOR EACH ROW
    EXECUTE PROCEDURE protect_critical_roles();
    
CREATE OR REPLACE FUNCTION protect_role_names()
RETURNS TRIGGER AS $$
BEGIN
    -- Si le rôle n'est pas supprimable, on interdit aussi de changer son nom
    IF OLD.can_be_deleted = FALSE AND NEW.name <> OLD.name THEN
        RAISE EXCEPTION 'Interdit : Le nom du rôle système "%" ne peut pas être modifié.', OLD.name;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER trigger_protect_role_names
    BEFORE UPDATE ON roles
    FOR EACH ROW
    EXECUTE PROCEDURE protect_role_names();
