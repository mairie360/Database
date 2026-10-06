BEGIN;
SELECT plan(9);

-- MAIR-480 (releases/v1.10.0): the phone is a country (ISO 3166-1 alpha-2) plus a
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
