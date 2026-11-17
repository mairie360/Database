BEGIN;
SELECT plan(12);

-- Second factor managed by Core (MAIR-805): user_totp (sealed TOTP secret, anti-replay step) and
-- user_backup_codes (Argon2 hashes of the single-use codes), releases/v3.5.0/01.

INSERT INTO users (id, first_name, last_name, email, password)
VALUES (9950, 'Totp', 'Marker', 'totp.marker@example.com', '$argon2id$v=19$m=16,t=2,p=1$c2FsdHNhbHQ$aGFzaGhhc2g'),
       (9951, 'Totp', 'Other', 'totp.other@example.com', NULL);

SELECT has_table('user_totp', 'user_totp exists');
SELECT has_table('user_backup_codes', 'user_backup_codes exists');
SELECT col_is_pk('user_totp', 'user_id', 'one TOTP secret per user');
SELECT col_is_fk('user_backup_codes', 'user_id', 'backup codes belong to a user');

-- Enrolment: the row starts pending, the secret is mandatory and cannot be empty.
SELECT lives_ok(
    $$INSERT INTO user_totp (user_id, secret_encrypted) VALUES (9950, '\xdeadbeef'::bytea)$$,
    'enrolment creates a pending secret'
);
SELECT is((SELECT confirmed_at FROM user_totp WHERE user_id = 9950), NULL, 'a new secret is not confirmed yet');
SELECT throws_ok(
    $$INSERT INTO user_totp (user_id, secret_encrypted) VALUES (9951, '\x'::bytea)$$,
    '23514', NULL, 'an empty secret is refused'
);
SELECT throws_ok(
    $$INSERT INTO user_totp (user_id, secret_encrypted) VALUES (9950, '\xaa'::bytea)$$,
    '23505', NULL, 'a user has a single TOTP secret'
);
SELECT throws_ok(
    $$UPDATE user_totp SET last_used_step = -1 WHERE user_id = 9950$$,
    '23514', NULL, 'a negative time step is refused'
);

-- Backup codes: hash only, spent once.
SELECT lives_ok(
    $$INSERT INTO user_backup_codes (user_id, code_hash)
      SELECT 9950, '$argon2id$v=19$m=16,t=2,p=1$c2FsdHNhbHQ$code' || g FROM generate_series(1, 10) g$$,
    'ten backup code hashes are stored'
);
SELECT throws_ok(
    $$INSERT INTO user_backup_codes (user_id, code_hash) VALUES (9950, '  ')$$,
    '23514', NULL, 'an empty code hash is refused'
);
SELECT throws_ok(
    $$INSERT INTO user_backup_codes (user_id, code_hash) VALUES (9999999, 'x')$$,
    '23503', NULL, 'a backup code needs an existing user'
);

-- Erasure of the account is covered by 41_gdpr_erasure_test.sql (anonymize_user deletes both tables).

SELECT * FROM finish();
ROLLBACK;
