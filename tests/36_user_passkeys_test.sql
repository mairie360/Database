BEGIN;
SELECT plan(12);

-- MAIR-505: passkeys (WebAuthn credentials) of an account, releases/v3.1.0/03.
-- Core_API is the relying party: the schema only stores the credentials and
-- keeps them attached to their account.

---
--- 1. SCHEMA
---

-- Test 1
SELECT has_table('user_passkeys', 'The user_passkeys table must exist');

-- Test 2: the credential id is kept as bytes (compared byte for byte).
SELECT col_type_is('user_passkeys', 'credential_id', 'bytea',
    'credential_id is a BYTEA');

-- Test 3: the credential is an opaque JSON document for the schema.
SELECT col_type_is('user_passkeys', 'passkey', 'jsonb', 'passkey is a JSONB');

-- Test 4: the per-user list and the exclusion list of a registration are indexed.
SELECT has_index('user_passkeys', 'idx_user_passkeys_user_id', ARRAY['user_id'],
    'user_passkeys is indexed by user');

---
--- 2. CONSTRAINTS
---

INSERT INTO users (id, first_name, last_name, email, password)
VALUES (9800, 'Pass', 'Key', 'passkey@passkeys.test', NULL);

-- Test 5
SELECT lives_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label)
      VALUES (9800, decode(repeat('ab', 32), 'hex'), '{"cred": {"counter": 0}}', 'Téléphone')$$,
    'A passkey can be registered for a user'
);

-- Test 6: a credential id belongs to one account only.
SELECT throws_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label)
      VALUES (9800, decode(repeat('ab', 32), 'hex'), '{"cred": {"counter": 0}}', 'Doublon')$$,
    '23505',
    NULL,
    'A credential id cannot be registered twice'
);

-- Test 7: WebAuthn credential ids are at least 16 bytes long.
SELECT throws_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label)
      VALUES (9800, decode('0102', 'hex'), '{"cred": {"counter": 0}}', 'Court')$$,
    '23514',
    NULL,
    'A credential id shorter than 16 bytes is refused'
);

-- Test 8: the credential is a JSON object, never a scalar or an array.
SELECT throws_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label)
      VALUES (9800, decode(repeat('cd', 32), 'hex'), '"not an object"', 'Scalaire')$$,
    '23514',
    NULL,
    'The passkey must be a JSON object'
);

-- Test 9
SELECT throws_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label)
      VALUES (9800, decode(repeat('cd', 32), 'hex'), '{}', '   ')$$,
    '23514',
    NULL,
    'The label must not be blank'
);

-- Test 10: a passkey always belongs to an existing user.
SELECT throws_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label)
      VALUES (989898, decode(repeat('ef', 32), 'hex'), '{}', 'Orphan')$$,
    '23503',
    NULL,
    'A passkey cannot reference an unknown user'
);

---
--- 3. LIFECYCLE
---

-- Test 11: Core_API rewrites the credential after an authentication (counter, flags).
SELECT lives_ok(
    $$UPDATE user_passkeys
      SET passkey = '{"cred": {"counter": 1}}', last_used_at = now()
      WHERE credential_id = decode(repeat('ab', 32), 'hex')$$,
    'The credential and last_used_at can be updated after an authentication'
);

-- Test 12: archiving keeps the passkeys (restore_user() brings the account back as it was).
DELETE FROM v_users_active WHERE id = 9800;
SELECT is(
    (SELECT count(*)::INT FROM user_passkeys WHERE user_id = 9800),
    1,
    'An archived user keeps their passkeys'
);

SELECT * FROM finish();
ROLLBACK;
