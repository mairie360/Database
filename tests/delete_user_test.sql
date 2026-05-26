BEGIN;

-- CORRECTION : Il y a exactement 10 tests (assertions) dans ce script.
SELECT plan(10);

---
--- 1. PRÉPARATION DES DONNÉES (Un utilisateur avec une vraie activité)
---

-- Précaution : S'assurer qu'un utilisateur 1 (Admin) existe pour posséder le 2ème projet
INSERT INTO users (id, first_name, last_name, email, password, status, is_archived)
VALUES (1, 'Admin', 'System', 'admin.test@example.com', 'hash', 'active', FALSE)
ON CONFLICT (id) DO NOTHING;

-- Création de l'utilisateur de test
INSERT INTO users (id, first_name, last_name, email, password, status, is_archived)
VALUES (9999, 'Alice', 'Merveille', 'alice.test@example.com', 'hash_pw', 'active', FALSE);

-- Activité : Création d'une session
-- CORRECTION : On ne fait QUE l'insertion de session. Ton trigger 'trigger_log_login'
-- va automatiquement créer le premier log de LOGIN dans connection_logs !
INSERT INTO sessions (user_id, user_is_archived, token_hash, device_info)
VALUES (9999, FALSE, 'token_alice_123', 'Chrome/Windows');

-- Activité : Attribution d'un rôle
INSERT INTO roles (id, name, description) VALUES (9999, 'test_role_alice', 'Role temporaire') ON CONFLICT DO NOTHING;
INSERT INTO user_roles (user_id, role_id) VALUES (9999, 9999);

-- Activité : Propriétaire d'un projet et membre d'un autre
INSERT INTO projects (id, title, owner_id) VALUES (9998, 'Projet possédé par Alice', 9999);
INSERT INTO projects (id, title, owner_id) VALUES (9999, 'Projet public', 1);
INSERT INTO project_members (project_id, user_id) VALUES (9999, 9999);

-- Activité : Tâche assignée
INSERT INTO tasks (id, project_id, title, assigned_to)
VALUES (9999, 9999, 'Tâche importante d''Alice', 9999);


---
--- 2. EXÉCUTION DE L'ACTION (Soft Delete)
---
-- On simule la suppression de l'utilisateur via l'API/Système
SELECT delete_user(9999);


---
--- 3. TESTS DE L'ARCHIVAGE LOGIQUE (Soft Delete)
---
SELECT ok(
    (SELECT is_archived FROM users WHERE id = 9999),
    'L''utilisateur 9999 doit être marqué comme archivé (is_archived = TRUE)'
);

SELECT is(
    (SELECT status FROM users WHERE id = 9999),
    'archived'::varchar,
    'Le statut de l''utilisateur doit être mis à jour sur "archived"'
);


---
--- 4. TESTS DES SUPPRESSIONS MANUELLES (Droits, Accès, Participations)
---
SELECT is_empty(
    $$ SELECT 1 FROM sessions WHERE user_id = 9999 $$,
    'Toutes les sessions actives de l''utilisateur doivent avoir été supprimées'
);

SELECT is_empty(
    $$ SELECT 1 FROM user_roles WHERE user_id = 9999 $$,
    'Les permissions et rôles de l''utilisateur doivent être révoqués'
);

SELECT is_empty(
    $$ SELECT 1 FROM project_members WHERE user_id = 9999 $$,
    'L''utilisateur doit être retiré de tous les projets en tant que membre'
);

SELECT is_empty(
    $$ SELECT 1 FROM projects WHERE owner_id = 9999 $$,
    'Les projets dont l''utilisateur était l''unique propriétaire doivent être supprimés (ou transférés selon ta logique métier)'
);


---
--- 5. TESTS DE DÉSASSIGNATION (ON DELETE SET NULL manuel)
---
SELECT ok(
    (SELECT assigned_to IS NULL FROM tasks WHERE id = 9999),
    'La tâche assignée à l''utilisateur doit maintenant être orpheline (assigned_to = NULL)'
);


---
--- 6. TESTS DE LA CONSERVATION DE L'HISTORIQUE (Cascade ON UPDATE)
---
SELECT ok(
    EXISTS(SELECT 1 FROM connection_logs WHERE user_id = 9999 AND user_is_archived = TRUE),
    'Les historiques comme les connection_logs doivent être conservés intacts, avec la clé user_is_archived basculée à TRUE'
);

SELECT is(
    (SELECT count(*)::int FROM connection_logs WHERE user_id = 9999),
    2, -- 1 LOGIN (trigger à l'insert de la session) + 1 LOGOUT/CLEANUP (trigger au delete de la session)
    'Les logs de connexion doivent comporter le LOGIN initial ET le nouveau LOGOUT'
);


---
--- 7. TESTS DE SÉCURITÉ (Double suppression)
---
SELECT throws_ok(
    $$ SELECT delete_user(9999) $$,
    'P0001',
    'L''utilisateur avec l''ID 9999 n''existe pas ou est déjà archivé.',
    'La fonction doit rejeter la tentative de suppression d''un utilisateur déjà archivé'
);

-- Fin de l'exécution des tests
SELECT * FROM finish();

ROLLBACK;
