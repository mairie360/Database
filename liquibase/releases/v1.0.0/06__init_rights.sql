-- 1. Table des droits (Table de jointure)
CREATE TABLE rights (
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE INDEX idx_rights_permission_id ON rights(permission_id);

-- 2. Insertion des droits par défaut

-- Droits pour l'Admin
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Admin'
AND (
    -- Liste des permissions pour l'admin
    (res.name = 'users' AND p.action IN ('read_all', 'create', 'update_all', 'delete_all')) OR
    (res.name = 'roles' AND p.action IN ('read_all', 'create', 'update_all', 'delete_all')) OR
    (res.name = 'sessions' AND p.action IN ('read_all', 'create', 'update')) OR
    (res.name = 'session_setting' AND p.action IN ('read_all', 'update')) -- Correction du nom de la ressource
)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits pour le Maire
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Maire'
AND (
    -- Liste des permissions pour le maire
    (res.name = 'users' AND p.action IN ('read_all', 'update')) OR
    (res.name = 'roles' AND p.action IN ('read_all')) OR
    (res.name = 'sessions' AND p.action IN ('read', 'create', 'update'))
)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits pour les Responsables
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Responsable'
AND (
    -- Liste des permissions pour les responsables
    (res.name = 'users' AND p.action IN ('read_all', 'update', 'delete')) OR
    (res.name = 'roles' AND p.action IN ('read_all')) OR
    (res.name = 'sessions' AND p.action IN ('read', 'create', 'update'))
)
ON CONFLICT (role_id, permission_id) DO NOTHING;


-- Droits pour l'User
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'User'
AND (
    -- Liste des permissions pour un user
    (res.name = 'users' AND p.action IN ('read', 'update', 'delete')) OR
    (res.name = 'roles' AND p.action IN ('read')) OR
    (res.name = 'sessions' AND p.action IN ('read', 'create', 'update'))
)
ON CONFLICT (role_id, permission_id) DO NOTHING;


-- Droits pour le Guest
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Guest'
AND (
    -- Liste des permissions pour un guest
    (res.name = 'users' AND p.action IN ('read')) OR
    (res.name = 'sessions' AND p.action IN ('read', 'create', 'update'))
)
ON CONFLICT (role_id, permission_id) DO NOTHING;
