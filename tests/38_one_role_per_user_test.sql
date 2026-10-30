BEGIN;
SELECT plan(12);

-- MAIR-564 (releases/v3.1.0): a user holds one role. user_roles is keyed by the user
-- (07__one_role_per_user.sql), and tr_user_roles_replace_default
-- (repeatable/roles/trigger_replace_default_role.sql) lets a role replace the default Guest
-- given by tr_users_default_role_guest. The migration of existing accounts is checked by
-- tests/upgrade/01_upgrade_test.sql.

-- Test 1
SELECT col_is_pk('user_roles', 'user_id', 'user_roles is keyed by the user alone');

INSERT INTO users (id, first_name, last_name, email, password, status) VALUES
    (9800, 'Una', 'Role', 'una@roles.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active'),
    (9801, 'Gus', 'Guest', 'gus@roles.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active'),
    (9802, 'Fix', 'Ture', 'fix@roles.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active'),
    (9803, 'Pro', 'Mote', 'pro@roles.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active');
INSERT INTO user_roles (user_id, role_id) VALUES
    (9800, (SELECT id FROM roles WHERE name = 'User')),
    (9803, (SELECT id FROM roles WHERE name = 'User'));
-- 9801 and 9802 get the default Guest, as an account committed before its role is written.
SET CONSTRAINTS ALL IMMEDIATE;

-- Test 2: a second role is refused.
SELECT throws_ok(
    $$INSERT INTO user_roles (user_id, role_id)
      VALUES (9800, (SELECT id FROM roles WHERE name = 'Responsable'))$$,
    '23505',
    NULL,
    'A user who holds a role cannot be given a second one'
);

-- Test 3: Guest does not replace a real role either.
SELECT throws_ok(
    $$INSERT INTO user_roles (user_id, role_id)
      VALUES (9800, (SELECT id FROM roles WHERE name = 'Guest'))$$,
    '23505',
    NULL,
    'Guest cannot be added next to a real role'
);

-- Test 4
SELECT results_eq(
    $$SELECT r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = 9800$$,
    $$VALUES ('User'::varchar)$$,
    'The refused inserts leave the role in place'
);

-- Test 5-6: a role written after the default Guest replaces it (registration then grant).
SELECT lives_ok(
    $$INSERT INTO user_roles (user_id, role_id)
      VALUES (9801, (SELECT id FROM roles WHERE name = 'Responsable'))$$,
    'A role can be given to an account that only holds the default Guest'
);

SELECT results_eq(
    $$SELECT r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = 9801$$,
    $$VALUES ('Responsable'::varchar)$$,
    'The role replaces the default Guest'
);

-- Test 7: same through ON CONFLICT DO NOTHING (the mairie360_api_lib test fixtures).
INSERT INTO user_roles (user_id, role_id)
VALUES (9802, (SELECT id FROM roles WHERE name = 'Admin'))
ON CONFLICT DO NOTHING;

SELECT results_eq(
    $$SELECT r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = 9802$$,
    $$VALUES ('Admin'::varchar)$$,
    'An ON CONFLICT DO NOTHING writer replaces the default Guest too'
);

-- Test 8-9: Core_API's grant (upsert on the user) replaces the role.
SELECT results_eq(
    $$INSERT INTO user_roles (user_id, role_id)
      VALUES (9803, (SELECT id FROM roles WHERE name = 'Maire'))
      ON CONFLICT (user_id) DO UPDATE SET role_id = EXCLUDED.role_id
      WHERE user_roles.role_id IS DISTINCT FROM EXCLUDED.role_id
      RETURNING role_id$$,
    $$SELECT id FROM roles WHERE name = 'Maire'$$,
    'Granting a role through the upsert replaces the former one'
);

SELECT is(
    (SELECT count(*)::INT FROM user_roles WHERE user_id = 9803),
    1,
    'The upsert leaves one role'
);

-- Test 10: granting the role already held changes nothing (Core_API answers 409).
SELECT is_empty(
    $$INSERT INTO user_roles (user_id, role_id)
      VALUES (9803, (SELECT id FROM roles WHERE name = 'Maire'))
      ON CONFLICT (user_id) DO UPDATE SET role_id = EXCLUDED.role_id
      WHERE user_roles.role_id IS DISTINCT FROM EXCLUDED.role_id
      RETURNING role_id$$,
    'Granting the role already held returns no row'
);

-- Test 11: create_user() writes exactly the requested role.
SELECT create_user('Cree', 'Seul', 'cree@roles.test',
                   '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g',
                   (SELECT id FROM roles WHERE name = 'User'));
SET CONSTRAINTS ALL IMMEDIATE;

SELECT results_eq(
    $$SELECT r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id
      JOIN users u ON u.id = ur.user_id WHERE u.email = 'cree@roles.test'$$,
    $$VALUES ('User'::varchar)$$,
    'create_user() gives one role'
);

-- Test 12
SELECT is_empty(
    $$SELECT user_id FROM user_roles GROUP BY user_id HAVING count(*) > 1$$,
    'No account holds more than one role'
);

SELECT * FROM finish();
ROLLBACK;
