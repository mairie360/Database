BEGIN;
SELECT plan(18);

-- repeatable/common/seed_test_accounts.sql seeds the accounts of the external attack
-- campaigns through seed_test_accounts(password_hash), only when -Dtest_accounts_password is
-- passed. docker-compose-test.yml passes it (TEST_ACCOUNTS_PASSWORD), as the Deploiment chart
-- does on dev and staging: tests 1-5 check what that real migration left, the others call the
-- function with the values Liquibase would pass.

CREATE TEMP TABLE expected_accounts (email TEXT PRIMARY KEY, role_name TEXT NOT NULL);
INSERT INTO expected_accounts VALUES
    ('attack.admin@example.invalid', 'Admin'),
    ('attack.maire@example.invalid', 'Maire'),
    ('attack.responsable@example.invalid', 'Responsable'),
    ('attack.user@example.invalid', 'User'),
    ('attack.user.b@example.invalid', 'User'),
    ('attack.user.c@example.invalid', 'User'),
    ('attack.guest@example.invalid', 'Guest');

-- Test 1: the migration run with the parameter created the seven accounts.
SELECT set_eq(
    $$SELECT email::TEXT FROM users WHERE email LIKE 'attack.%@example.invalid'$$,
    $$SELECT email FROM expected_accounts$$,
    'MAIR-1185: the migration with test_accounts_password seeds the seven campaign accounts'
);

-- Test 2: one role per account, as listed (one per role, three User).
SELECT set_eq(
    $$SELECT u.email::TEXT, r.name::TEXT FROM users u
      JOIN user_roles ur ON ur.user_id = u.id JOIN roles r ON r.id = ur.role_id
      WHERE u.email LIKE 'attack.%@example.invalid'$$,
    $$SELECT email, role_name FROM expected_accounts$$,
    'MAIR-1185: each campaign account holds its role'
);

-- Test 3: usable at once by an automated client.
SELECT is(
    (SELECT count(*)::INT FROM users
     WHERE email LIKE 'attack.%@example.invalid'
       AND status = 'active' AND is_archived = FALSE AND first_connect = FALSE),
    7,
    'MAIR-1185: the campaign accounts are active, not archived, without first-connect step'
);

-- Test 4
SELECT is(
    (SELECT count(DISTINCT password)::INT FROM users WHERE email LIKE 'attack.%@example.invalid'),
    1,
    'MAIR-1185: the campaign accounts share the supplied hash'
);

-- Test 5
SELECT is(
    (SELECT password FROM users WHERE email = 'attack.guest@example.invalid')::TEXT,
    '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g',
    'MAIR-1185: the stored password is the hash passed to the migration'
);

-- Test 6: only the migration user may call the function.
SELECT ok(
    NOT has_function_privilege('core_api', 'seed_test_accounts(text)', 'EXECUTE')
    AND NOT has_function_privilege('public', 'seed_test_accounts(text)', 'EXECUTE'),
    'MAIR-1185: seed_test_accounts is not executable by the API roles nor PUBLIC'
);

-- Test 7: a plaintext password is refused.
SELECT throws_ok(
    $$SELECT seed_test_accounts('Passw0rd-in-clear')$$,
    'P0001',
    'test_accounts_password must be an argon2id hash',
    'MAIR-1185: a plaintext test_accounts_password is refused'
);

-- Tests 8-12: business journey. A campaign archived one account, promoted the Guest and
-- changed a password; the next deploy (runAlways, here with a rotated hash) puts every
-- account back in its known state without duplicating anything.
UPDATE users SET is_archived = TRUE, status = 'archived'
WHERE email = 'attack.user.b@example.invalid';
UPDATE user_roles SET role_id = (SELECT id FROM roles WHERE name = 'Admin')
WHERE user_id = (SELECT id FROM users WHERE email = 'attack.guest@example.invalid');
UPDATE users SET first_connect = TRUE
WHERE email = 'attack.maire@example.invalid';

SELECT is(
    seed_test_accounts('$argon2id$v=19$m=16,t=2,p=1$cm90YXRlZA$cm90YXRlZGhhc2g'),
    7,
    'MAIR-1185: replaying the seed writes the seven accounts again'
);

SELECT is(
    (SELECT count(*)::INT FROM users WHERE email LIKE 'attack.%@example.invalid'),
    7,
    'MAIR-1185: replaying the seed does not duplicate an account'
);

SELECT set_eq(
    $$SELECT u.email::TEXT, r.name::TEXT FROM users u
      JOIN user_roles ur ON ur.user_id = u.id JOIN roles r ON r.id = ur.role_id
      WHERE u.email LIKE 'attack.%@example.invalid'$$,
    $$SELECT email, role_name FROM expected_accounts$$,
    'MAIR-1185: replaying the seed gives every account its role back'
);

SELECT is(
    (SELECT count(*)::INT FROM users
     WHERE email LIKE 'attack.%@example.invalid'
       AND status = 'active' AND is_archived = FALSE AND first_connect = FALSE
       AND password = '$argon2id$v=19$m=16,t=2,p=1$cm90YXRlZA$cm90YXRlZGhhc2g'),
    7,
    'MAIR-1185: replaying the seed restores and rotates every account'
);

SELECT is(
    (SELECT count(*)::INT FROM users WHERE id = 1 AND email LIKE 'attack.%'),
    0,
    'MAIR-1185: the seed never touches the admin account (id 1)'
);

-- Tests 13-16: an instance that never received the parameter (prod) holds none of these
-- accounts: without it, the seed creates nothing.
DELETE FROM user_roles
WHERE user_id IN (SELECT id FROM users WHERE email LIKE 'attack.%@example.invalid');
DELETE FROM users WHERE email LIKE 'attack.%@example.invalid';

SELECT is(
    seed_test_accounts(NULL),
    0,
    'MAIR-1185: without test_accounts_password the seed writes nothing'
);

SELECT is(
    seed_test_accounts(''),
    0,
    'MAIR-1185: an empty test_accounts_password writes nothing'
);

SELECT is(
    (SELECT count(*)::INT FROM users WHERE email LIKE 'attack.%@example.invalid'),
    0,
    'MAIR-1185: without test_accounts_password no campaign account exists'
);

-- Test 16: an account created by hand with the same address in another case is reused.
INSERT INTO users (first_name, last_name, email, password, status)
VALUES ('Hand', 'Made', 'Attack.Guest@Example.invalid',
        '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'offline');
DO $$ BEGIN PERFORM seed_test_accounts('$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'); END $$;
SELECT is(
    (SELECT count(*)::INT FROM users WHERE lower(email) = 'attack.guest@example.invalid'),
    1,
    'MAIR-1185: an existing account whose address differs only by case is reused'
);

-- Tests 17-18: an administrator account that holds a campaign address is refused, not reset.
DELETE FROM user_roles
WHERE user_id IN (SELECT id FROM users WHERE email ILIKE 'attack.%@example.invalid');
DELETE FROM users WHERE email ILIKE 'attack.%@example.invalid';
UPDATE users SET email = 'attack.guest@example.invalid' WHERE id = 1;

SELECT throws_ok(
    $$SELECT seed_test_accounts('$argon2id$v=19$m=16,t=2,p=1$Y29sbGlk$Y29sbGlkZWQ')$$,
    'P0001',
    'test account attack.guest@example.invalid is the administrator account (users.id = 1)',
    'MAIR-1185: the seed refuses an administrator holding a campaign address'
);

SELECT is(
    (SELECT r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = 1),
    'Admin',
    'MAIR-1185: the administrator keeps its role when its address collides'
);

SELECT * FROM finish();
ROLLBACK;
