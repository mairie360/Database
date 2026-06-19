BEGIN;
SELECT plan(18);

---
--- 1. PRÉPARATION
---

INSERT INTO users (id, first_name, last_name, email, password, status, is_archived)
VALUES (411, 'Random', 'User', 'random@test.com', 'pwd', 'active', false);
INSERT INTO roles (name) VALUES ('Admin'), ('User') ON CONFLICT DO NOTHING;
-- On n'utilise QUE la ressource 'groups'
INSERT INTO resources (name) VALUES ('groups') ON CONFLICT DO NOTHING;

-- Configuration de la permission globale de test sur 'groups'
INSERT INTO permissions (resource_id, action)
SELECT id, 'delete_all' FROM resources WHERE name = 'groups'
ON CONFLICT DO NOTHING;

-- Configuration des permissions ACL simples de test sur 'groups'
INSERT INTO permissions (resource_id, action)
SELECT id, 'read' FROM resources WHERE name = 'groups'
ON CONFLICT DO NOTHING;

INSERT INTO permissions (resource_id, action)
SELECT id, 'update' FROM resources WHERE name = 'groups'
ON CONFLICT DO NOTHING;

INSERT INTO rights (role_id, permission_id)
SELECT (SELECT id FROM roles WHERE name = 'Admin'), id
FROM permissions WHERE action = 'delete_all'
AND resource_id = (SELECT id FROM resources WHERE name = 'groups')
ON CONFLICT DO NOTHING;

-- Nettoyage des données de test
DELETE FROM group_members WHERE user_id IN (400, 401, 402);
DELETE FROM access_control WHERE user_id IN (400, 401, 402);
DELETE FROM groups WHERE id IN (50, 60);
DELETE FROM users WHERE id IN (400, 401, 402);

INSERT INTO users (id, first_name, last_name, email, password, status, is_archived)
VALUES
    (400, 'Admin', 'User', 'admin_acl@test.com', 'pwd', 'active', false),
    (401, 'Standard', 'User', 'user_acl@test.com', 'pwd', 'active', false),
    (402, 'Guest', 'User', 'guest_acl@test.com', 'pwd', 'active', false);

INSERT INTO user_roles (user_id, role_id)
VALUES (400, (SELECT id FROM roles WHERE name = 'Admin'));

INSERT INTO groups (id, owner_id, name)
VALUES (50, 401, 'Ownership Group')
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
-- L'admin (400) a 'delete_all' sur 'groups', donc check_access(..., 'groups', 'delete', 50) doit passer
SELECT is(check_access(400, 'groups', 'delete', 50), 1, 'Admin accède globalement via delete_all');
SELECT is((SELECT result FROM access_logs ORDER BY id DESC LIMIT 1), 'GRANTED', 'Audit: GRANTED');

---
--- 4. NIVEAU 2 - PROPRIÉTÉ (3 tests)
---
SELECT is(owner_id, 401, 'Le groupe 50 appartient bien à 401') FROM public.groups WHERE id = 50;
SELECT is(check_access(411, 'groups', 'read', 50), 0, 'Un user random échoue par OWNERSHIP'); -- Ajout d'une sécurité
SELECT is(check_access(401, 'groups', 'read', 50), 1, 'Le propriétaire accède par OWNERSHIP');
SELECT is((SELECT reason FROM access_logs WHERE user_id = 401 ORDER BY timestamp DESC LIMIT 1), 'OWNERSHIP', 'Raison: OWNERSHIP');

---
--- 5. NIVEAU 3 - ACL INDIVIDUELLE (2 tests)
---
INSERT INTO access_control (user_id, resource_id, resource_instance_id, permission_id)
VALUES (402, (SELECT id FROM resources WHERE name = 'groups'), 50,
       (SELECT id FROM permissions WHERE action = 'read' AND resource_id = (SELECT id FROM resources WHERE name = 'groups') LIMIT 1));

SELECT is(check_access(402, 'groups', 'read', 50), 1, 'Guest accède via ACL individuelle');
SELECT is((SELECT reason FROM access_logs ORDER BY id DESC LIMIT 1), 'INDIVIDUAL_ACL', 'Raison: INDIVIDUAL_ACL');

---
--- 6. NIVEAU 4 - ACL GROUPE (2 tests)
---
INSERT INTO groups (id, owner_id, name) VALUES (60, 400, 'Alpha Group');
INSERT INTO group_members (group_id, user_id) VALUES (60, 402);

INSERT INTO access_control (group_id, resource_id, resource_instance_id, permission_id)
VALUES (60, (SELECT id FROM resources WHERE name = 'groups'), 50,
       (SELECT id FROM permissions WHERE action = 'update' AND resource_id = (SELECT id FROM resources WHERE name = 'groups') LIMIT 1));

SELECT is(check_access(402, 'groups', 'update', 50), 1, 'Guest accède via ACL de groupe');
SELECT is((SELECT reason FROM access_logs ORDER BY id DESC LIMIT 1), 'GROUP_ACL', 'Raison: GROUP_ACL');

---
--- 7. REFUS (2 tests)
---
-- Personne n'a le droit 'archive' sur le groupe 50
SELECT is(check_access(402, 'groups', 'archive', 50), 0, 'Refusé par défaut');
SELECT is((SELECT result FROM access_logs ORDER BY id DESC LIMIT 1), 'DENIED', 'Log: DENIED');

---
--- 8. RESSOURCES INEXISTANTES / 404 (3 tests)
---
SELECT is(check_access(402, 'groups', 'read', 9999), -1, 'Retourne -1 (404) si l''ID de l''instance n''existe pas');
SELECT is(check_access(402, 'grouppps', 'read', 50), -1, 'Retourne -1 (404) si la table de ressource n''existe pas');

SELECT is(
    (SELECT COUNT(*)::INT FROM access_logs WHERE reason IN ('INSTANCE_NOT_FOUND', 'RESOURCE_TABLE_NOT_FOUND')),
    0,
    'Vérification qu''aucun log d''audit n''est écrit pour les erreurs 404'
);

SELECT * FROM finish();
ROLLBACK;
