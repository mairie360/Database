BEGIN;
SELECT plan(12);

---
--- 1. TESTS DE STRUCTURE & DONNÉES INITIALES
---

SELECT has_table('roles');
SELECT has_table('user_roles');

SELECT is(
    (SELECT count(*)::INT FROM roles WHERE name IN ('Admin', 'User', 'Guest')),
    3,
    'Les 3 rôles par défaut doivent être présents'
);

---
--- 2. PROTECTION DES RÔLES SYSTÈMES
---

-- Test protection contre la suppression
SELECT throws_ok(
    $$ DELETE FROM roles WHERE name = 'Admin' $$,
    'Suppression impossible : le rôle "Admin" est critique pour le système.',
    'Le trigger doit empêcher la suppression du rôle Admin'
);

-- Test protection contre le renommage
SELECT throws_ok(
    $$ UPDATE roles SET name = 'SuperUser' WHERE name = 'Admin' $$,
    'Modification interdite : le nom du rôle "Admin" est réservé.',
    'Le trigger doit empêcher de renommer le rôle Admin'
);

---
--- 3. ATTRIBUTION ET CYCLE DE VIE USER/ROLE
---

-- Préparation : Un utilisateur de test
INSERT INTO users (id, first_name, last_name, email, password, status)
VALUES (200, 'Marc', 'RoleTest', 'marc@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active');

-- Test attribution de rôle
INSERT INTO user_roles (user_id, role_id)
VALUES (200, (SELECT id FROM roles WHERE name = 'User'));

SELECT ok(
    EXISTS (SELECT 1 FROM user_roles WHERE user_id = 200),
    'Marc doit avoir le rôle User'
);

---
--- 4. TEST DE SÉCURITÉ : ARCHIVAGE ET RÔLES
---

-- Scénario : on archive l'utilisateur. Aucun trigger ne nettoie user_roles à
-- l'archivage : l'utilisateur archivé garde ses rôles pour que restore_user()
-- le remette en service tel qu'il était (MAIR-535).
SELECT lives_ok(
    $$ UPDATE users SET is_archived = TRUE, status = 'archived' WHERE id = 200 $$,
    'L''archivage d''un utilisateur qui a un rôle doit réussir'
);

SELECT is(
    (SELECT count(*)::INT FROM user_roles WHERE user_id = 200),
    1,
    'L''archivage conserve les rôles de Marc (user_roles n''est pas nettoyé)'
);

SELECT lives_ok(
    $$ SELECT restore_user(200) $$,
    'restore_user remet Marc en service'
);

SELECT is(
    (SELECT role_id FROM user_roles WHERE user_id = 200),
    (SELECT id FROM roles WHERE name = 'User'),
    'Après restore_user, Marc retrouve son rôle User'
);

---
--- 5. TIMESTAMPS
---

SELECT ok(
    updated_at >= created_at,
    'Le timestamp updated_at doit être cohérent'
) FROM roles WHERE name = 'Admin';

-- update_roles_modtime (BEFORE UPDATE) réécrit updated_at, même si l'UPDATE tente de le fixer
UPDATE roles SET description = description, updated_at = '2000-01-01 00:00:00+00' WHERE name = 'Guest';
SELECT is(
    (SELECT updated_at FROM roles WHERE name = 'Guest'),
    now(),
    'update_roles_modtime remet updated_at à now() à chaque UPDATE d''un rôle'
);

SELECT * FROM finish();
ROLLBACK;
