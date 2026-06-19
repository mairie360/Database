-- 1. Table des Groupes
CREATE TABLE groups (
    id SERIAL PRIMARY KEY,
    owner_id INT NOT NULL,
    name VARCHAR(64) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- La FK doit pointer vers la clé composite de users
    CONSTRAINT fk_groups_owner FOREIGN KEY (owner_id)
        REFERENCES users(id) ON DELETE RESTRICT
);

-- 2. Table de Liaison (Membres)
CREATE TABLE group_members (
    group_id INT REFERENCES groups(id) ON DELETE CASCADE,
    user_id INT NOT NULL,
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (group_id, user_id),
    CONSTRAINT fk_group_members_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
);

---
-- 3. INSERTION DES DONNÉES DE SÉCURITÉ
---

-- Ajout de la ressource "groups"
INSERT INTO resources (name, description) VALUES
    ('groups', 'Gestion des groupes d''utilisateurs')
ON CONFLICT (name) DO NOTHING;

-- Création des permissions pour "groups"
INSERT INTO permissions (resource_id, action)
SELECT res.id, t.action
FROM resources res,
(VALUES
    ('read_all'), ('read'), ('create'),
    ('update_all'), ('update'),
    ('delete_all'), ('delete')
) AS t(action)
WHERE res.name = 'groups'
ON CONFLICT (resource_id, action) DO NOTHING;

-- Droits Admin
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Admin' AND res.name = 'groups'
AND p.action IN ('read_all', 'create', 'update_all', 'delete_all')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Maire
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Maire' AND res.name = 'groups'
AND p.action IN ('read_all', 'create', 'update_all', 'delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Responsable
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Responsable' AND res.name = 'groups'
AND p.action IN ('read', 'create', 'update', 'delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits User
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'User' AND res.name = 'groups'
AND p.action IN ('read')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Guest
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Guest' AND res.name = 'groups'
AND p.action IN ('read')
ON CONFLICT (role_id, permission_id) DO NOTHING;
