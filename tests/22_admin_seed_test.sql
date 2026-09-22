BEGIN;
SELECT plan(7);

-- MAIR-170: repeatable/common/create_admin.sql seeds the id = 1 admin
-- account. docker-compose-test.yml runs the migration without
-- -Dadmin_email / -Dadmin_password, so the parameterized branches below are
-- exercised here by replaying their exact statements with literal values --
-- the same statements Liquibase would run once admin_email/admin_password
-- resolve to real, substituted text instead of the unset placeholder.

-- Test 1: without secrets, the template account is seeded.
SELECT is(
    (SELECT email FROM users WHERE id = 1),
    'template.email@gmail.com'::varchar,
    'The unparameterized migration seeds the template admin email'
);

-- Test 2: ...and is not marked for a forced password change.
SELECT is(
    (SELECT first_connect FROM users WHERE id = 1),
    FALSE,
    'The template admin account does not force a first-connect password change'
);

-- Test 3: replaying the user_roles seed (as create_admin.sql does on every
-- changeset run) must not fail or duplicate the Admin role assignment.
INSERT INTO user_roles (user_id, role_id)
VALUES (1, 1)
ON CONFLICT DO NOTHING;

SELECT is(
    (SELECT count(*)::INT FROM user_roles WHERE user_id = 1 AND role_id = 1),
    1,
    'Replaying the admin role seed is idempotent'
);

-- Test 4: an instance whose id = 1 still carries the template credentials
-- gets replaced by the supplied admin_email/admin_password, forced to
-- change it on first login.
UPDATE users
SET email = 'mayor@town.example',
    password = '$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    first_connect = TRUE
WHERE id = 1
  AND email = 'template.email@gmail.com'
  AND password = '$argon2id$v=19$m=19456,t=2,p=1$/iKF9PbiDRDs4EKPjlIIhg$UKx9vfwwps250mEP/bYp63CXbEnQGULeUAhDq+az9Aw';

SELECT is(
    (SELECT email FROM users WHERE id = 1),
    'mayor@town.example'::varchar,
    'A template admin account is replaced by the supplied email'
);

-- Test 5
SELECT is(
    (SELECT first_connect FROM users WHERE id = 1),
    TRUE,
    'Replacing the template admin account forces a first-connect password change'
);

-- Test 6-7: replaying the same changeset (a later sync, or a second
-- deployment run) with different values must not touch the account anymore,
-- since it no longer carries the template credentials.
UPDATE users
SET email = 'someone-else@town.example',
    password = '$argon2id$v=19$m=19456,t=2,p=1$BBBBBBBBBBBBBBBBBBBBBB$BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
    first_connect = TRUE
WHERE id = 1
  AND email = 'template.email@gmail.com'
  AND password = '$argon2id$v=19$m=19456,t=2,p=1$/iKF9PbiDRDs4EKPjlIIhg$UKx9vfwwps250mEP/bYp63CXbEnQGULeUAhDq+az9Aw';

-- Test 6
SELECT is(
    (SELECT email FROM users WHERE id = 1),
    'mayor@town.example'::varchar,
    'A customized admin account is left untouched by a later changeset replay'
);

-- Test 7: ...its password is untouched too.
SELECT is(
    (SELECT password FROM users WHERE id = 1),
    '$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'::varchar,
    'A customized admin account keeps its own password across a later changeset replay'
);

SELECT * FROM finish();
ROLLBACK;
