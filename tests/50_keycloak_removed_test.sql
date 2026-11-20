BEGIN;
SELECT plan(8);

-- Core is the only account system (releases/v4.0.0/01): the objects of the Keycloak SSO are gone and
-- the erasure no longer propagates to it.

SELECT hasnt_table('user_identities', 'the table of the SSO identities is dropped');
SELECT hasnt_view('v_users_sso_export', 'the export view of the Keycloak migration is dropped');
SELECT hasnt_function('link_user_identity', 'link_user_identity() is dropped');
SELECT hasnt_function('resolve_user_identity', 'resolve_user_identity() is dropped');

-- An account without a local password is still allowed: it sets one through the e-mailed link.
SELECT col_is_null('users', 'password', 'users.password stays nullable');

-- Test 6: the erasure steps no longer include Keycloak.
INSERT INTO users (id, first_name, last_name, email, password) VALUES
    (9950, 'Step', 'Check', 'keycloak.removed@example.com', '$argon2id$v=19$m=16,t=2,p=1$c2FsdHNhbHQ$aGFzaGhhc2g');
SELECT throws_ok(
    $$INSERT INTO erasure_steps (user_id, step) VALUES (9950, 'keycloak')$$,
    '23514',
    NULL,
    'erasure_steps refuses the keycloak step'
);
SELECT lives_ok(
    $$INSERT INTO erasure_steps (user_id, step) SELECT 9950, s FROM unnest(ARRAY['resend', 's3', 'redis', 'backup_key', 'database']) s$$,
    'erasure_steps keeps the other steps'
);

-- Test 8: the targets of an erasure carry no Keycloak subject.
SELECT is(
    fn_erasure_targets(9950),
    '{"user_id": 9950, "email": "keycloak.removed@example.com"}'::JSONB,
    'fn_erasure_targets gives the e-mail only'
);

SELECT * FROM finish();
ROLLBACK;
