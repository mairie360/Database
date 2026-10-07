BEGIN;
SELECT plan(13);

-- MAIR-480 (releases/v3.0.0): the phone is a country (ISO 3166-1 alpha-2) plus a
-- national number (digits only), both or neither.

SELECT has_column('users', 'phone_country', 'users has a phone_country column');

SELECT ok(
    EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_phone' AND convalidated),
    'chk_users_phone is validated'
);

SELECT lives_ok(
    $$INSERT INTO users (first_name, last_name, email, password, phone_country, phone_number)
      VALUES ('Lea', 'Phone', 'lea.phone@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'FR', '612345678')$$,
    'A country and a national number are accepted'
);

SELECT lives_ok(
    $$INSERT INTO users (first_name, last_name, email, password)
      VALUES ('Noe', 'Phone', 'noe.phone@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g')$$,
    'No phone at all is accepted'
);

SELECT throws_ok(
    $$INSERT INTO users (first_name, last_name, email, password, phone_number)
      VALUES ('Sam', 'Phone', 'sam.phone@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', '612345678')$$,
    '23514',
    NULL,
    'A number without a country is refused'
);

-- Legacy writers (French national number, no country) are converted by
-- trg_users_normalize_legacy_phone.
INSERT INTO users (first_name, last_name, email, password, phone_number) VALUES
    ('Old', 'Mobile', 'old.mobile@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', '0612345678'),
    ('Old', 'Reunion', 'old.reunion@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', '0692123456'),
    ('Old', 'Code', 'old.code@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', '33145678901'),
    ('Old', 'Empty', 'old.empty@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', '');

SELECT results_eq(
    $$SELECT email::TEXT, phone_country::TEXT, phone_number::TEXT FROM users
      WHERE email LIKE 'old.%@test.com' ORDER BY email$$,
    $$VALUES ('old.code@test.com', 'FR', '145678901'),
             ('old.empty@test.com', NULL, NULL),
             ('old.mobile@test.com', 'FR', '612345678'),
             ('old.reunion@test.com', 'RE', '692123456')$$,
    'A legacy French number written without its country is converted'
);

SELECT lives_ok(
    $$UPDATE users SET phone_number = '0798765432' WHERE email = 'old.empty@test.com'$$,
    'A legacy update of the number alone is converted too'
);

SELECT is(
    (SELECT phone_country || ' ' || phone_number FROM users WHERE email = 'old.empty@test.com'),
    'FR 798765432',
    'The legacy update stores the country and the national number'
);

SELECT throws_ok(
    $$INSERT INTO users (first_name, last_name, email, password, phone_number)
      VALUES ('Old', 'Foreign', 'old.foreign@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', '4412345678')$$,
    '23514',
    NULL,
    'A legacy number that is not French is still refused'
);

SELECT throws_ok(
    $$UPDATE users SET phone_number = NULL WHERE email = 'lea.phone@test.com'$$,
    '23514',
    NULL,
    'A country without a number is refused'
);

SELECT throws_ok(
    $$UPDATE users SET phone_country = 'fr' WHERE email = 'lea.phone@test.com'$$,
    '23514',
    NULL,
    'A country that is not two uppercase letters is refused'
);

SELECT throws_ok(
    $$UPDATE users SET phone_number = '+33612345678' WHERE email = 'lea.phone@test.com'$$,
    '23514',
    NULL,
    'A number with something else than digits is refused'
);

SELECT create_user('Ana', 'Phone', 'ana.phone@test.com',
                   '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g',
                   (SELECT id FROM roles WHERE name = 'User'),
                   '470123456', 'offline', 'BE');

SELECT is(
    (SELECT phone_country || ' ' || phone_number FROM users WHERE email = 'ana.phone@test.com'),
    'BE 470123456',
    'create_user stores the phone country'
);

SELECT * FROM finish();
ROLLBACK;
