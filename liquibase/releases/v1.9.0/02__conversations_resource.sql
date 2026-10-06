-- MAIR-478: declare `conversations` as an access-controlled resource.
--
-- releases/v1.0.0/12__init_messaging.sql granted the roles their rights on
-- `conversations`, but the resource and its permissions were never declared,
-- so those inserts matched nothing and check_access() answered -1 (unknown
-- resource) for any conversation. Message_API now asks check_access() whether
-- an agent may delete a conversation (`delete`: global `delete_all`, or an
-- individual or group ACL on that conversation).
INSERT INTO resources (name, description) VALUES
    ('conversations', 'Messaging conversations')
ON CONFLICT (name) DO NOTHING;

INSERT INTO permissions (resource_id, action)
SELECT res.id, t.action
FROM resources res,
     (VALUES ('read_all'), ('read'), ('create'), ('update_all'), ('update'),
             ('delete_all'), ('delete')) AS t(action)
WHERE res.name = 'conversations'
ON CONFLICT (resource_id, action) DO NOTHING;

-- The rights 12__init_messaging.sql meant to give.
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN (VALUES
        ('Admin', 'read_all'), ('Admin', 'create'), ('Admin', 'update_all'), ('Admin', 'delete_all'),
        ('Maire', 'read'), ('Maire', 'create'), ('Maire', 'update'), ('Maire', 'delete'),
        ('Responsable', 'read'), ('Responsable', 'create'), ('Responsable', 'update'), ('Responsable', 'delete'),
        ('User', 'read'), ('User', 'create'), ('User', 'update'), ('User', 'delete'),
        ('Guest', 'read')
     ) AS g(role_name, action) ON g.role_name = r.name
JOIN permissions p ON p.action = g.action
JOIN resources res ON res.id = p.resource_id AND res.name = 'conversations'
ON CONFLICT (role_id, permission_id) DO NOTHING;
