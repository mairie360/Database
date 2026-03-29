-- 1. Table des Groupes
CREATE TABLE groups (
    id SERIAL PRIMARY KEY,
    -- ON DELETE RESTRICT empêche de supprimer l'utilisateur s'il possède encore un groupe
    owner_id INT NOT NULL REFERENCES users(id) ON DELETE RESTRICT, 
    name VARCHAR(64) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Table de Liaison (Membres)
CREATE TABLE group_users (
    group_id INT REFERENCES groups(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (group_id, user_id)
);

-- 3. Fonction pour ajouter automatiquement l'owner comme membre
CREATE OR REPLACE FUNCTION add_owner_to_group_members()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO group_users (group_id, user_id)
    VALUES (NEW.id, NEW.owner_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Déclenchement du Trigger
CREATE TRIGGER trigger_add_owner_as_member
AFTER INSERT ON groups
FOR EACH ROW
EXECUTE FUNCTION add_owner_to_group_members();

-- 1. Correction de la Vue (Nom de table et Resource ID)
CREATE OR REPLACE VIEW v_securable_groups AS
SELECT 
    g.*, 
    (SELECT id FROM resources WHERE name = 'groups') as resource_id
FROM groups g;

-- 2. Insertion des Permissions (Correction de la syntaxe VALUES)
INSERT INTO permissions (resource_id, action)
SELECT res.id, t.action 
FROM resources res, 
(VALUES 
    ('read_all'), ('read'), ('create'), 
    ('update_all'), ('update'), 
    ('delete_all'), ('delete')
) AS t(action)
WHERE res.name = 'groups';

-- 3. Droits pour l'Admin (Total contrôle)
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Admin' 
AND res.name = 'groups'
AND p.action IN ('read_all', 'create', 'update_all', 'delete_all');

-- 4. Droits pour le User (Actions sur ses propres données)
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'User' 
AND res.name = 'groups'
AND p.action IN ('read', 'update', 'delete', 'create');

-- 5. Droits pour le Guest (Lecture seule)
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Guest' 
AND res.name = 'groups'
AND p.action IN ('read');