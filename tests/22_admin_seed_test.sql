BEGIN;
SELECT plan(17);

-- MAIR-170 / MAIR-413: repeatable/common/create_admin.sql seeds the id = 1
-- admin account through seed_admin_account(email, password, allow_template).
-- docker-compose-test.yml runs the migration with -Dallow_template_admin=true
-- and no credentials; the other branches are exercised below by calling the
-- function with the values Liquibase would pass.

-- Test 1: with allow_template_admin, the template account is seeded on a
-- reserved, undeliverable domain.
SELECT is(
    (SELECT email FROM users WHERE id = 1),
    'admin@example.invalid'::varchar,
    'The template admin account uses the reserved example.invalid domain'
);

-- Test 2
SELECT is(
    (SELECT first_connect FROM users WHERE id = 1),
    FALSE,
    'The template admin account does not force a first-connect password change'
);

-- Test 3
SELECT ok(
    is_admin(1),
    'The template admin account has the Admin role'
);

-- Test 4-5: replaying the template seed is idempotent.
SELECT lives_ok(
    $$SELECT seed_admin_account(NULL, NULL, TRUE)$$,
    'Replaying the template seed does not fail'
);

SELECT is(
    (SELECT count(*)::INT FROM user_roles WHERE user_id = 1 AND role_id = 1),
    1,
    'Replaying the template seed does not duplicate the Admin role assignment'
);

-- Test 6: without credentials nor allow_template_admin, a database still on
-- the template account fails the migration.
SELECT throws_ok(
    $$SELECT seed_admin_account(NULL, NULL, FALSE)$$,
    'P0001',
    'admin_email and admin_password must be supplied to seed the admin account (users.id = 1)',
    'Without credentials, the template admin account is refused'
);

-- Test 7-9: an instance created before MAIR-169 / MAIR-413 still holds the
-- seed password in plaintext and the third-party address (grandfathered by
-- the NOT VALID chk_users_password_hashed). The template seed hashes the
-- password (same value) and moves the address to example.invalid.
ALTER TABLE users DROP CONSTRAINT chk_users_password_hashed;
UPDATE users
SET email = 'template.email@gmail.com', password = 'password_template', first_connect = TRUE
WHERE id = 1;
ALTER TABLE users ADD CONSTRAINT chk_users_password_hashed
    CHECK (password ~ '^\$argon2id\$v=\d+\$m=\d+,t=\d+,p=\d+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$') NOT VALID;

SELECT lives_ok(
    $$SELECT seed_admin_account(NULL, NULL, TRUE)$$,
    'Replaying the template seed on a legacy plaintext admin does not fail'
);

SELECT results_eq(
    $$SELECT email::TEXT, password::TEXT FROM users WHERE id = 1$$,
    $$VALUES ('admin@example.invalid',
              '$argon2id$v=19$m=19456,t=2,p=1$/iKF9PbiDRDs4EKPjlIIhg$UKx9vfwwps250mEP/bYp63CXbEnQGULeUAhDq+az9Aw')$$,
    'A legacy template admin gets the hashed password and the example.invalid address'
);

SELECT is(
    (SELECT first_connect FROM users WHERE id = 1),
    FALSE,
    'The migrated template admin account does not force a first-connect password change'
);

-- Test 10-11: supplied credentials replace the template account, which must
-- change its password on first login.
SELECT seed_admin_account(
    'mayor@town.example',
    '$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    FALSE
);

SELECT is(
    (SELECT email FROM users WHERE id = 1),
    'mayor@town.example'::varchar,
    'A template admin account is replaced by the supplied email'
);

SELECT is(
    (SELECT first_connect FROM users WHERE id = 1),
    TRUE,
    'Replacing the template admin account forces a first-connect password change'
);

-- Test 12-13: a later replay with other credentials leaves it alone.
SELECT seed_admin_account(
    'someone-else@town.example',
    '$argon2id$v=19$m=19456,t=2,p=1$BBBBBBBBBBBBBBBBBBBBBB$BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
    FALSE
);

SELECT is(
    (SELECT email FROM users WHERE id = 1),
    'mayor@town.example'::varchar,
    'A customized admin account is left untouched by a later changeset replay'
);

SELECT is(
    (SELECT password FROM users WHERE id = 1),
    '$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'::varchar,
    'A customized admin account keeps its own password across a later changeset replay'
);

-- Test 14-15: once provisioned, a replay without credentials is a no-op.
SELECT lives_ok(
    $$SELECT seed_admin_account(NULL, NULL, FALSE)$$,
    'A provisioned instance replays the seed without credentials'
);

SELECT is(
    (SELECT email FROM users WHERE id = 1),
    'mayor@town.example'::varchar,
    'A replay without credentials leaves the provisioned admin untouched'
);

-- Test 16: allow_template_admin never adds a template account next to a
-- provisioned admin.
SELECT seed_admin_account(NULL, NULL, TRUE);

SELECT is(
    (SELECT count(*)::INT FROM users WHERE email IN ('admin@example.invalid', 'template.email@gmail.com')),
    0,
    'No template account is created next to a provisioned admin'
);

-- Test 17
SELECT ok(
    NOT has_function_privilege('core_api', 'seed_admin_account(text, text, boolean)', 'EXECUTE'),
    'API roles cannot run seed_admin_account'
);

SELECT * FROM finish();
ROLLBACK;
