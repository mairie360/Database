BEGIN;
SELECT plan(3);

-- MAIR-413 (releases/v2.0.0): e-mail addresses are unique regardless of case.

SELECT ok(
    EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'users'
          AND indexname = 'uq_users_email_lower'
          AND indexdef LIKE 'CREATE UNIQUE INDEX % (lower((email)::text))'
    ),
    'users has a unique index on lower(email)'
);

INSERT INTO users (first_name, last_name, email, password)
VALUES ('Camille', 'Case', 'camille.case@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');

SELECT throws_ok(
    $$INSERT INTO users (first_name, last_name, email, password)
      VALUES ('Camille', 'Upper', 'Camille.CASE@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g')$$,
    '23505',
    NULL,
    'An e-mail differing only by case is refused'
);

SELECT lives_ok(
    $$INSERT INTO users (first_name, last_name, email, password)
      VALUES ('Camille', 'Other', 'camille.other@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g')$$,
    'A different e-mail is accepted'
);

SELECT * FROM finish();
ROLLBACK;
