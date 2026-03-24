CREATE TABLE rights (
    role_id INT REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INT REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE INDEX idx_rights_permission_id ON rights(permission_id);

INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Admin' 
AND (
    -- Liste des permissions pour l'admin
    (res.name = 'users' AND p.action IN ('read_all', 'create', 'update', 'delete')) OR
    (res.name = 'roles' AND p.action IN ('read_all', 'create', 'update', 'delete')) OR
    (res.name = 'sessions' AND p.action IN ('read_all', 'create', 'update', 'delete')) OR
    (res.name = 'session_settings' AND p.action IN ('read_all', 'update'))
);


INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'User' 
AND (
    -- Liste des permissions pour un user
    (res.name = 'users' AND p.action IN ('read', 'update', 'delete')) OR
    (res.name = 'roles' AND p.action IN ('read')) OR
    (res.name = 'sessions' AND p.action IN ('read', 'create', 'update', 'delete'))
);

INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Guest' 
AND (
    -- Liste des permissions pour un user
    (res.name = 'users' AND p.action IN ('read')) OR
    (res.name = 'sessions' AND p.action IN ('read', 'create', 'update', 'delete'))
);