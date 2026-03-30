BEGIN;
SELECT plan(14);

---
--- 1. PRÉPARATION (On force les noms au pluriel pour correspondre à tes tables réelles)
---
INSERT INTO roles (name) VALUES ('Admin'), ('User') ON CONFLICT DO NOTHING;
-- On s'assure que la ressource s'appelle 'groups' pour matcher le nom de la table
INSERT INTO resources (name) VALUES ('user'), ('groups') ON CONFLICT DO NOTHING;

-- On s'assure que les permissions existent
INSERT INTO permissions (resource_id, action) 
SELECT id, 'read_all' FROM resources WHERE name = 'user'
ON CONFLICT DO NOTHING;

INSERT INTO rights (role_id, permission_id)
SELECT (SELECT id FROM roles WHERE name = 'Admin'), id 
FROM permissions WHERE action = 'read_all' 
AND resource_id = (SELECT id FROM resources WHERE name = 'user')
ON CONFLICT DO NOTHING;

INSERT INTO users (id, first_name, last_name, email, password, status)
VALUES 
    (400, 'Admin', 'User', 'admin_acl@test.com', 'pwd', 'active'),
    (401, 'Standard', 'User', 'user_acl@test.com', 'pwd', 'active'),
    (402, 'Guest', 'User', 'guest_acl@test.com', 'pwd', 'active')
ON CONFLICT DO NOTHING;

INSERT INTO user_roles (user_id, role_id) 
VALUES (400, (SELECT id FROM roles WHERE name = 'Admin'))
ON CONFLICT DO NOTHING;

---
--- 2. STRUCTURE & TRIGGERS (3 tests)
---
SELECT has_table('access_control');
SELECT has_table('access_logs');
SELECT has_function('check_access', ARRAY['integer', 'varchar', 'varchar', 'integer']);

---
--- 3. NIVEAU 1 - GLOBAL (2 tests)
---
SELECT ok(check_access(400, 'user', 'read', 401), 'Admin accède via read_all');
SELECT is((SELECT result FROM access_logs ORDER BY id DESC LIMIT 1), 'GRANTED', 'Audit: GRANTED');

---
--- 4. NIVEAU 2 - PROPRIÉTÉ
---
-- On s'assure d'abord que les ressources sont propres
DELETE FROM groups WHERE id = 50;
DELETE FROM users WHERE id = 401;

INSERT INTO users (id, first_name, last_name, email, password, status, is_archived)
VALUES (401, 'Owner', 'User', 'owner@test.com', 'pwd', 'active', false);

INSERT INTO groups (id, owner_id, owner_is_archived, name) 
VALUES (50, 401, false, 'Ownership Group');

-- Diagnostic simple
SELECT is(owner_id, 401, 'Le groupe 50 appartient bien à 401') FROM public.groups WHERE id = 50;

-- Appel de la fonction
SELECT ok(check_access(401, 'groups', 'read', 50), 'Le propriétaire accède par OWNERSHIP');
SELECT is((SELECT reason FROM access_logs WHERE user_id = 401 ORDER BY timestamp DESC LIMIT 1), 'OWNERSHIP', 'Raison: OWNERSHIP');

---
--- 5. NIVEAU 3 - ACL INDIVIDUELLE (2 tests)
---
-- On utilise 'read' (simple)
INSERT INTO access_control (user_id, resource_id, resource_instance_id, permission_id)
VALUES (402, (SELECT id FROM resources WHERE name = 'groups'), 50, 
       (SELECT id FROM permissions WHERE action = 'read' AND resource_id = (SELECT id FROM resources WHERE name = 'groups') LIMIT 1));

SELECT ok(check_access(402, 'groups', 'read', 50), 'Guest accède via ACL individuelle');
SELECT is((SELECT reason FROM access_logs ORDER BY id DESC LIMIT 1), 'INDIVIDUAL_ACL', 'Raison: INDIVIDUAL_ACL');

---
--- 6. NIVEAU 4 - ACL GROUPE (2 tests)
---
-- On crée un groupe 'Alpha' (ID 60) dont Guest (402) est membre
INSERT INTO groups (id, owner_id, name) VALUES (60, 400, 'Alpha Group') ON CONFLICT DO NOTHING;
INSERT INTO group_users (group_id, user_id) VALUES (60, 402) ON CONFLICT DO NOTHING;

-- On donne au GROUPE 60 le droit 'update' sur le GROUPE 50
INSERT INTO access_control (group_id, resource_id, resource_instance_id, permission_id)
VALUES (60, (SELECT id FROM resources WHERE name = 'groups'), 50, 
       (SELECT id FROM permissions WHERE action = 'update' AND resource_id = (SELECT id FROM resources WHERE name = 'groups') LIMIT 1));

SELECT ok(check_access(402, 'groups', 'update', 50), 'Guest accède via ACL de groupe');
SELECT is((SELECT reason FROM access_logs ORDER BY id DESC LIMIT 1), 'GROUP_ACL', 'Raison: GROUP_ACL');

---
--- 7. REFUS (2 tests)
---
SELECT ok(NOT check_access(402, 'user', 'delete', 400), 'Refusé par défaut');
SELECT is((SELECT result FROM access_logs ORDER BY id DESC LIMIT 1), 'DENIED', 'Log: DENIED');

SELECT * FROM finish();
ROLLBACK;