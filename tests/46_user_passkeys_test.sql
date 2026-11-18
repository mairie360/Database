BEGIN;
SELECT plan(17);

-- Passkeys (WebAuthn) managed by Core (MAIR-810): releases/v3.7.0/01. Several per user, the credential
-- identifier is unique, they go with the account, only core_api touches them.

INSERT INTO users (id, first_name, last_name, email, password)
VALUES (9970, 'Passkey', 'Marker', 'passkey.marker@example.com', NULL),
       (9971, 'Passkey', 'Other', 'passkey.other@example.com', NULL);

SELECT has_table('user_passkeys', 'user_passkeys exists');
SELECT col_is_fk('user_passkeys', 'user_id', 'a passkey belongs to a user');
SELECT col_is_unique('user_passkeys', 'credential_id', 'a credential identifier is unique');
SELECT has_index('user_passkeys', 'idx_user_passkeys_user_id', 'user_id', 'the passkeys of a user are indexed');

SELECT lives_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label)
      VALUES (9970, '\x01'::bytea, '{"k":1}'::jsonb, 'Laptop'), (9970, '\x02'::bytea, '{"k":2}'::jsonb, 'Phone')$$,
    'a user registers several passkeys'
);
SELECT is((SELECT last_used_at FROM user_passkeys WHERE credential_id = '\x01'::bytea), NULL, 'a new passkey was never used');
SELECT throws_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label) VALUES (9971, '\x01'::bytea, '{}'::jsonb, 'Copy')$$,
    '23505', NULL, 'the same credential cannot be registered twice, even by another user'
);
SELECT throws_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label) VALUES (9971, '\x'::bytea, '{}'::jsonb, 'Empty')$$,
    '23514', NULL, 'an empty credential identifier is refused'
);
SELECT throws_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label) VALUES (9971, '\x03'::bytea, '{}'::jsonb, '   ')$$,
    '23514', NULL, 'a blank label is refused'
);
SELECT throws_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label) VALUES (9999999, '\x04'::bytea, '{}'::jsonb, 'Ghost')$$,
    '23503', NULL, 'a passkey needs an existing user'
);


-- Name of the passkey manager (releases/v3.10.0/01): optional, never blank.
SELECT has_column('user_passkeys', 'provider', 'a passkey can carry the name of its manager');
SELECT col_is_null('user_passkeys', 'provider', 'the manager is optional (unknown authenticator)');
SELECT lives_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label, provider)
      VALUES (9971, '\x05'::bytea, '{}'::jsonb, 'Phone', 'iCloud Keychain')$$,
    'a passkey keeps the name of its manager'
);
SELECT throws_ok(
    $$INSERT INTO user_passkeys (user_id, credential_id, passkey, label, provider) VALUES (9971, '\x06'::bytea, '{}'::jsonb, 'Blank', '  ')$$,
    '23514', NULL, 'a blank manager name is refused (NULL says unknown)'
);

-- Cascade.
DELETE FROM user_passkeys WHERE user_id = 9970 AND credential_id = '\x02'::bytea;
SELECT is((SELECT count(*)::INT FROM user_passkeys WHERE user_id = 9970), 1, 'a passkey can be removed alone');
SELECT lives_ok($$DELETE FROM users WHERE id = 9970$$, 'a user row can go');
SELECT is((SELECT count(*)::INT FROM user_passkeys WHERE user_id = 9970), 0, 'the passkeys go with the user');

SELECT * FROM finish();
ROLLBACK;
