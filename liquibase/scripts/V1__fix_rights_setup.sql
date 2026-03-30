-- Clean rights
DELETE FROM rights;

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
    (res.name = 'session_settings' AND p.action IN ('read_all', 'update')) OR
    (res.name = 'groups' AND p.action IN ('read_all', 'create', 'update_all', 'delete_all'))
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
    (res.name = 'sessions' AND p.action IN ('read', 'create', 'update', 'delete')) OR
    (res.name = 'groups' AND p.action IN ('read'))
);

INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Guest' 
AND (
    -- Liste des permissions pour un user
    (res.name = 'users' AND p.action IN ('read')) OR
    (res.name = 'sessions' AND p.action IN ('read', 'create', 'update', 'delete')) OR
    (res.name = 'groups' AND p.action IN ('read'))
);