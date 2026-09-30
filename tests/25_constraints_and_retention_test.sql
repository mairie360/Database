BEGIN;
SELECT plan(12);

-- MAIR-236: every constraint is validated, access_logs has dated partitions,
-- and fn_apply_retention_policies() applies the retention policies.

SELECT is(
    (SELECT count(*)::int FROM pg_constraint
     WHERE NOT convalidated AND conname <> 'chk_users_password_hashed'),
    0,
    'no constraint is left NOT VALID (except the legacy password guard)'
);

SELECT ok(
    (SELECT convalidated FROM pg_constraint WHERE conname = 'chk_users_password_hashed')
    OR EXISTS (SELECT 1 FROM users WHERE password IS NOT NULL AND password !~ '^\$argon2id\$'),
    'chk_users_password_hashed is validated unless plaintext passwords remain'
);

---
-- Partitions
---
SELECT cmp_ok(
    (SELECT count(*)::int FROM pg_inherits
     WHERE inhparent = 'public.access_logs'::regclass
       AND inhrelid <> 'public.access_logs_default'::regclass),
    '>=', 4,
    'access_logs has the current month and 3 upcoming monthly partitions'
);

SELECT ok(
    to_regclass('public.access_logs_y' || to_char(now(), 'YYYY') || 'm' || to_char(now(), 'MM')) IS NOT NULL,
    'the current month partition follows the access_logs_yYYYYmMM naming'
);

SELECT is(fn_ensure_access_logs_partitions(3), 0, 'ensuring partitions again is idempotent');

SELECT throws_ok(
    'SELECT fn_ensure_access_logs_partitions(-1)', 'P0001', NULL,
    'a negative horizon is refused'
);

-- A row from a month that has no partition yet lands in DEFAULT, then is moved
-- into its own partition when the partition is created.
INSERT INTO access_logs (user_id, resource_name, action, result, timestamp)
VALUES (1, 'users', 'read', 'GRANTED', date_trunc('month', now()) + interval '10 months');

SELECT is(
    (SELECT count(*)::int FROM access_logs_default WHERE resource_name = 'users' AND timestamp >= now() + interval '9 months'),
    1, 'a row outside every partition falls in the DEFAULT partition'
);

SELECT is(fn_ensure_access_logs_partitions(10), 7, 'the missing partitions up to +10 months are created');

SELECT is(
    (SELECT count(*)::int FROM access_logs_default WHERE timestamp >= now() + interval '9 months'),
    0, 'the row was moved out of the DEFAULT partition'
);

---
-- Retention
---
-- Old monthly partition (well past the 3 years) with a row in it.
CREATE TABLE access_logs_y2020m01 (LIKE access_logs INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE access_logs ATTACH PARTITION access_logs_y2020m01
    FOR VALUES FROM ('2020-01-01') TO ('2020-02-01');
INSERT INTO access_logs (user_id, resource_name, action, result, timestamp)
VALUES (1, 'users', 'read', 'GRANTED', '2020-01-15');

INSERT INTO users (id, first_name, last_name, email, password)
VALUES (2700, 'Ret', 'Ention', 'retention@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
INSERT INTO sessions (user_id, token_hash, created_at, expires_at, revoked_at)
VALUES (2700, 'old-session', now() - interval '1 year', now() - interval '1 year', NULL),
       (2700, 'recent-session', now(), now() + interval '1 day', NULL);
-- set_session_expiration() recomputes expires_at on INSERT: age it afterwards.
UPDATE sessions SET expires_at = now() - interval '1 year' WHERE token_hash = 'old-session';

SELECT results_eq(
    $$SELECT table_name, affected FROM fn_apply_retention_policies() ORDER BY table_name$$,
    $$VALUES ('access_logs'::text, 1::bigint), ('sessions'::text, 1::bigint)$$,
    'retention drops the expired partition and deletes the expired session'
);

SELECT is(to_regclass('public.access_logs_y2020m01'), NULL, 'the expired partition is gone');

SELECT is(
    (SELECT array_agg(token_hash) FROM sessions WHERE user_id = 2700),
    ARRAY['recent-session'],
    'only the recent session is kept'
);

SELECT * FROM finish();
ROLLBACK;
