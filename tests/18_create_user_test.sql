BEGIN;
SELECT plan(6);

-- Les rôles de base (Admin, Maire, Responsable, User, Guest) sont seedés par
-- 03__init_roles.sql.

-- Test 1: create_user exige un rôle (NULL rejeté)
SELECT throws_ok(
    $$SELECT create_user('Jean', 'Dupont', 'jean.dupont1@test.com', 'hash', NULL)$$,
    '23502',
    NULL,
    'create_user doit rejeter un rôle NULL'
);

-- Test 2: create_user rejette un rôle inexistant
SELECT throws_ok(
    $$SELECT create_user('Jean', 'Dupont', 'jean.dupont2@test.com', 'hash', -1)$$,
    '23503',
    NULL,
    'create_user doit rejeter un rôle inexistant'
);

-- Test 3: create_user réussit avec un rôle valide
SELECT lives_ok(
    format(
        'SELECT create_user(''Jean'', ''Dupont'', ''jean.dupont3@test.com'', ''hash'', %L)',
        (SELECT id FROM roles WHERE name = 'User')
    ),
    'create_user doit réussir avec un rôle valide'
);

-- Test 4: create_user attribue exactement le rôle demandé (pas Guest)
SELECT results_eq(
    $$
    SELECT r.name FROM user_roles ur
    JOIN roles r ON r.id = ur.role_id
    JOIN users u ON u.id = ur.user_id
    WHERE u.email = 'jean.dupont3@test.com'
    $$,
    $$VALUES ('User'::varchar)$$,
    'create_user doit attribuer exactement le rôle demandé'
);

-- Test 5: sécurité - un utilisateur inséré sans rôle reçoit Guest une fois la
-- transaction "terminée" (on force le trigger différé pour le test).
INSERT INTO users (first_name, last_name, email, password)
VALUES ('Sans', 'Role', 'sans.role@test.com', 'hash');

SET CONSTRAINTS ALL IMMEDIATE;

SELECT results_eq(
    $$
    SELECT r.name FROM user_roles ur
    JOIN roles r ON r.id = ur.role_id
    JOIN users u ON u.id = ur.user_id
    WHERE u.email = 'sans.role@test.com'
    $$,
    $$VALUES ('Guest'::varchar)$$,
    'Un utilisateur créé sans rôle doit recevoir le rôle Guest par défaut'
);

-- Test 6: le filet de sécurité ne doit pas ajouter Guest si un rôle a déjà
-- été assigné dans la même transaction avant que le trigger différé ne
-- s'exécute.
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO users (first_name, last_name, email, password)
VALUES ('Avec', 'Role', 'avec.role@test.com', 'hash');

INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.email = 'avec.role@test.com' AND r.name = 'Responsable';

SET CONSTRAINTS ALL IMMEDIATE;

SELECT results_eq(
    $$
    SELECT r.name FROM user_roles ur
    JOIN roles r ON r.id = ur.role_id
    JOIN users u ON u.id = ur.user_id
    WHERE u.email = 'avec.role@test.com'
    $$,
    $$VALUES ('Responsable'::varchar)$$,
    'Le filet de sécurité ne doit pas écraser un rôle déjà assigné'
);

SELECT * FROM finish();
ROLLBACK;
