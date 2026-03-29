-- 1. Table des Groupes
CREATE TABLE groups (
    id SERIAL PRIMARY KEY,
    owner_id INT NOT NULL,
    -- Ajout de la colonne de partitionnement pour la FK
    owner_is_archived BOOLEAN NOT NULL DEFAULT FALSE CHECK (owner_is_archived = FALSE),
    name VARCHAR(64) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- La FK doit pointer vers la clé composite de users
    CONSTRAINT fk_groups_owner FOREIGN KEY (owner_id, owner_is_archived) 
        REFERENCES users(id, is_archived) ON DELETE RESTRICT
);

-- 2. Table de Liaison (Membres)
CREATE TABLE group_users (
    group_id INT REFERENCES groups(id) ON DELETE CASCADE,
    user_id INT NOT NULL,
    -- Même logique ici pour le partitionnement
    user_is_archived BOOLEAN NOT NULL DEFAULT FALSE CHECK (user_is_archived = FALSE),
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    PRIMARY KEY (group_id, user_id),
    CONSTRAINT fk_group_users_user FOREIGN KEY (user_id, user_is_archived) 
        REFERENCES users(id, is_archived) ON DELETE CASCADE
);

-- 3. Fonction pour ajouter automatiquement l'owner comme membre
-- CORRECTION : Il faut passer owner_is_archived à la table group_users
CREATE OR REPLACE FUNCTION add_owner_to_group_members()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO group_users (group_id, user_id, user_is_archived)
    VALUES (NEW.id, NEW.owner_id, NEW.owner_is_archived);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Déclenchement du Trigger
CREATE TRIGGER trigger_add_owner_as_member
AFTER INSERT ON groups
FOR EACH ROW
EXECUTE FUNCTION add_owner_to_group_members();

-- --- LOGIQUE DE PERMISSIONS (Inchangée mais incluse pour complétude) ---

CREATE OR REPLACE VIEW v_securable_groups AS
SELECT 
    g.*, 
    (SELECT id FROM resources WHERE name = 'groups') as resource_id
FROM groups g;

INSERT INTO permissions (resource_id, action)
SELECT res.id, t.action 
FROM resources res, 
(VALUES 
    ('read_all'), ('read'), ('create'), 
    ('update_all'), ('update'), 
    ('delete_all'), ('delete')
) AS t(action)
WHERE res.name = 'groups';

-- Droits Admin
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Admin' AND res.name = 'groups'
AND p.action IN ('read_all', 'create', 'update_all', 'delete_all');

-- Droits User
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'User' AND res.name = 'groups'
AND p.action IN ('read', 'update', 'delete', 'create');

-- Droits Guest
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Guest' AND res.name = 'groups'
AND p.action IN ('read');