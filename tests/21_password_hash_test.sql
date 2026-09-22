BEGIN;
SELECT plan(8);

-- MAIR-169: users.password must hold only an argon2id hash from now on.
-- chk_users_password_hashed enforces this on every write, and
-- migrate_legacy_password() is the only sanctioned path to rewrite a legacy
-- plaintext row in place.

-- Test 1: a fresh insert with a plaintext password is rejected.
SELECT throws_ok(
    $$INSERT INTO users (first_name, last_name, email, password)
      VALUES ('Plain', 'Text', 'plaintext@test.com', 'not-a-hash')$$,
    '23514',
    NULL,
    'INSERT must reject a plaintext password'
);

-- Test 2: a fresh insert with an argon2id-shaped hash is accepted.
SELECT lives_ok(
    $$INSERT INTO users (id, first_name, last_name, email, password)
      VALUES (9600, 'Hashed', 'User', 'hashed@test.com',
              '$argon2id$v=19$m=19456,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g')$$,
    'INSERT must accept a well-formed argon2id hash'
);

-- Fire the deferred default-role-guest trigger now: ALTER TABLE below cannot
-- run while a trigger event on users is still pending.
SET CONSTRAINTS ALL IMMEDIATE;

-- Test 3: migrate_legacy_password refuses a value that is not an argon2id hash.
SELECT throws_ok(
    $$SELECT migrate_legacy_password(9600, 'not-a-hash')$$,
    '22023',
    NULL,
    'migrate_legacy_password must reject a non-hash value'
);

-- Reproduce a legacy row the way prod already has some: a plaintext password
-- that predates chk_users_password_hashed. The constraint (NOT VALID) only
-- checks writes from the moment it exists, so dropping and recreating it
-- around this one plaintext insert reproduces that history inside the test.
ALTER TABLE users DROP CONSTRAINT chk_users_password_hashed;
INSERT INTO users (id, first_name, last_name, email, password)
VALUES (9601, 'Legacy', 'User', 'legacy@test.com', 'still-plaintext');
ALTER TABLE users ADD CONSTRAINT chk_users_password_hashed
    CHECK (password ~ '^\$argon2id\$v=\d+\$m=\d+,t=\d+,p=\d+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$')
    NOT VALID;
SET CONSTRAINTS ALL IMMEDIATE;

-- Test 4: migrating a legacy plaintext row reports it changed something.
SELECT is(
    migrate_legacy_password(9601, '$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
    TRUE,
    'migrate_legacy_password must report the legacy row as migrated'
);

-- Test 5: the row now holds the hash, not the plaintext value.
SELECT is(
    (SELECT password FROM users WHERE id = 9601),
    '$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'::varchar,
    'migrate_legacy_password must overwrite the plaintext value with the hash'
);

-- Test 6: migrating an already-hashed row is a no-op (reports nothing changed).
SELECT is(
    migrate_legacy_password(9601, '$argon2id$v=19$m=19456,t=2,p=1$BBBBBBBBBBBBBBBBBBBBBB$BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'),
    FALSE,
    'migrate_legacy_password must be a no-op once the row is already hashed'
);

-- Test 7: ...and it must not have clobbered the existing hash with the new one.
SELECT is(
    (SELECT password FROM users WHERE id = 9601),
    '$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'::varchar,
    'migrate_legacy_password must not overwrite an already-migrated hash'
);

-- Test 8: the create_admin seed account is created with a hash, not a
-- plaintext password.
SELECT ok(
    (SELECT password FROM users WHERE id = 1)
        ~ '^\$argon2id\$v=\d+\$m=\d+,t=\d+,p=\d+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$',
    'The admin seed account must be created with an argon2id hash'
);

SELECT * FROM finish();
ROLLBACK;
