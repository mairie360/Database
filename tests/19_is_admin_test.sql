BEGIN;
SELECT plan(6);

-- Les rôles de base (Admin, Maire, Responsable, User, Guest) sont seedés par
-- 03__init_roles.sql. Le trigger différé tr_users_default_role_guest est forcé
-- via SET CONSTRAINTS ALL IMMEDIATE après chaque création.

INSERT INTO users (first_name, last_name, email, password)
VALUES ('Ada', 'Admin', 'ada.admin@test.com', 'hash');
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.email = 'ada.admin@test.com' AND r.name = 'Admin';
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO users (first_name, last_name, email, password)
VALUES ('Ulysse', 'User', 'ulysse.user@test.com', 'hash');
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.email = 'ulysse.user@test.com' AND r.name = 'User';
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO users (first_name, last_name, email, password)
VALUES ('Mathis', 'Multi', 'mathis.multi@test.com', 'hash');
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.email = 'mathis.multi@test.com' AND r.name IN ('User', 'Admin');
SET CONSTRAINTS ALL IMMEDIATE;

-- Guest attribué par le filet de sécurité
INSERT INTO users (first_name, last_name, email, password)
VALUES ('Gaston', 'Guest', 'gaston.guest@test.com', 'hash');
SET CONSTRAINTS ALL IMMEDIATE;

-- Test 1: un Admin est admin
SELECT ok(
    is_admin((SELECT id FROM users WHERE email = 'ada.admin@test.com')),
    'is_admin doit renvoyer vrai pour un utilisateur ayant le rôle Admin'
);

-- Test 2: un utilisateur avec plusieurs rôles dont Admin est admin
SELECT ok(
    is_admin((SELECT id FROM users WHERE email = 'mathis.multi@test.com')),
    'is_admin doit renvoyer vrai si Admin fait partie des rôles'
);

-- Test 3: un User n'est pas admin
SELECT ok(
    NOT is_admin((SELECT id FROM users WHERE email = 'ulysse.user@test.com')),
    'is_admin doit renvoyer faux pour un utilisateur ayant le rôle User'
);

-- Test 4: le Guest par défaut n'est pas admin (régression v1.2.0)
SELECT results_eq(
    $$
    SELECT r.name FROM user_roles ur
    JOIN roles r ON r.id = ur.role_id
    JOIN users u ON u.id = ur.user_id
    WHERE u.email = 'gaston.guest@test.com'
    $$,
    $$VALUES ('Guest'::varchar)$$,
    'Le filet de sécurité doit avoir attribué Guest'
);

SELECT ok(
    NOT is_admin((SELECT id FROM users WHERE email = 'gaston.guest@test.com')),
    'is_admin doit renvoyer faux pour un utilisateur ayant le rôle Guest par défaut'
);

-- Test 5: un utilisateur inexistant n'est pas admin
SELECT ok(
    NOT is_admin(-1),
    'is_admin doit renvoyer faux pour un utilisateur inexistant'
);

SELECT * FROM finish();
ROLLBACK;
