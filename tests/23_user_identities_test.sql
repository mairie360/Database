BEGIN;
SELECT plan(24);

-- MAIR-141: SSO identities. releases/v1.4.0 adds user_identities and makes
-- users.password nullable; repeatable/auth/ adds link_user_identity()
-- (the replayable write path of the Keycloak migration job),
-- resolve_user_identity() (the SSO login path) and v_users_sso_export
-- (what the job reads).

---
--- 1. SCHEMA
---

-- Test 1
SELECT has_table('user_identities', 'The user_identities table must exist');

-- Test 2
SELECT col_is_null('users', 'password', 'users.password must be nullable (SSO-only accounts)');

-- Test 3
SELECT has_trigger('user_identities', 'trg_user_identities_updated_at',
    'user_identities must refresh updated_at on UPDATE');

-- Test 4: an SSO-only account has no local password...
SELECT lives_ok(
    $$INSERT INTO users (id, first_name, last_name, email, password)
      VALUES (9700, 'Sso', 'Only', 'sso.only@identities.test', NULL)$$,
    'A user can be created without a local password'
);

-- Test 5: ...but a plaintext password is still rejected on a nullable column.
SELECT throws_ok(
    $$INSERT INTO users (first_name, last_name, email, password)
      VALUES ('Plain', 'Text', 'plaintext@identities.test', 'not-a-hash')$$,
    '23514',
    NULL,
    'A plaintext password is still rejected'
);

-- Test 6: the provider is a lowercase machine name.
SELECT throws_ok(
    $$INSERT INTO user_identities (user_id, provider, subject) VALUES (9700, 'KeyCloak', 'x')$$,
    '23514',
    NULL,
    'The provider must be a lowercase identifier'
);

-- Test 7
SELECT throws_ok(
    $$INSERT INTO user_identities (user_id, provider, subject) VALUES (9700, 'keycloak', '  ')$$,
    '23514',
    NULL,
    'The subject must not be blank'
);

---
--- 2. link_user_identity(): replayable migration
---

INSERT INTO users (id, first_name, last_name, email, password, status)
VALUES
    (9701, 'Alice', 'Active', 'alice@identities.test',
     '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active'),
    (9702, 'Bob', 'Other', 'bob@identities.test',
     '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active');
INSERT INTO user_roles (user_id, role_id)
VALUES
    (9701, (SELECT id FROM roles WHERE name = 'Maire')),
    (9701, (SELECT id FROM roles WHERE name = 'User'));
-- Fire the deferred default-role trigger now so 9700/9702 get Guest and
-- 9701 keeps exactly the roles above.
SET CONSTRAINTS ALL IMMEDIATE;

-- Test 8
SELECT throws_ok(
    $$SELECT link_user_identity(424242, 'keycloak', 'ghost')$$,
    '23503',
    NULL,
    'link_user_identity must refuse an unknown user'
);

-- Test 9: first run creates the link.
SELECT ok(
    link_user_identity(9701, 'keycloak', 'sub-alice') IS NOT NULL,
    'link_user_identity returns the identity id on first run'
);

-- Test 10
SELECT results_eq(
    $$SELECT user_id, provider, subject FROM user_identities WHERE user_id = 9701$$,
    $$VALUES (9701, 'keycloak'::varchar, 'sub-alice'::varchar)$$,
    'The identity row holds the provider and subject'
);

-- Test 11: replaying the same call is a no-op that returns the same id.
SELECT is(
    link_user_identity(9701, 'keycloak', 'sub-alice'),
    (SELECT id FROM user_identities WHERE user_id = 9701 AND provider = 'keycloak'),
    'Replaying link_user_identity returns the existing identity id'
);

-- Test 12
SELECT is(
    (SELECT count(*)::INT FROM user_identities WHERE user_id = 9701),
    1,
    'Replaying link_user_identity creates no duplicate'
);

-- Test 13: the provider re-issued the account (new subject): re-link in place.
SELECT lives_ok(
    $$SELECT link_user_identity(9701, 'keycloak', 'sub-alice-v2')$$,
    'A user can be re-linked to a new subject of the same provider'
);

-- Test 14
SELECT results_eq(
    $$SELECT subject FROM user_identities WHERE user_id = 9701 AND provider = 'keycloak'$$,
    $$VALUES ('sub-alice-v2'::varchar)$$,
    'Re-linking replaces the subject without adding a row'
);

-- Test 15: a subject is never silently moved to another account.
SELECT throws_ok(
    $$SELECT link_user_identity(9702, 'keycloak', 'sub-alice-v2')$$,
    '23505',
    NULL,
    'A subject already linked to another user is refused'
);

-- Test 16: one user, several providers.
SELECT lives_ok(
    $$SELECT link_user_identity(9701, 'franceconnect', 'fc-alice')$$,
    'A user can hold one identity per provider'
);

---
--- 3. resolve_user_identity(): SSO login
---

-- Test 17
SELECT is(
    resolve_user_identity('keycloak', 'sub-alice-v2'),
    9701,
    'resolve_user_identity returns the linked active user'
);

-- Test 18
SELECT is(
    resolve_user_identity('keycloak', 'unknown-subject'),
    NULL,
    'resolve_user_identity returns NULL for an unknown subject'
);

-- Test 19
SELECT is(
    resolve_user_identity('other-idp', 'sub-alice-v2'),
    NULL,
    'resolve_user_identity matches the provider, not just the subject'
);

-- Archive Alice through the soft-delete view.
DELETE FROM v_users_active WHERE id = 9701;

-- Test 20
SELECT is(
    resolve_user_identity('keycloak', 'sub-alice-v2'),
    NULL,
    'An archived user cannot sign in through the SSO'
);

-- Test 21: the link survives archiving...
SELECT is(
    (SELECT count(*)::INT FROM user_identities WHERE user_id = 9701),
    2,
    'Archiving a user keeps their identities'
);

-- Test 22: ...so a restored user signs in again as before.
SELECT restore_user(9701);
SELECT is(
    resolve_user_identity('keycloak', 'sub-alice-v2'),
    9701,
    'A restored user can sign in through the SSO again'
);

---
--- 4. v_users_sso_export: what the migration job reads
---

-- Test 23
SELECT results_eq(
    $$SELECT email, enabled, has_local_password, roles, identities
      FROM v_users_sso_export WHERE id = 9701$$,
    $$VALUES ('alice@identities.test'::varchar, TRUE, TRUE,
              ARRAY['Maire', 'User']::varchar[],
              '{"keycloak": "sub-alice-v2", "franceconnect": "fc-alice"}'::jsonb)$$,
    'The export lists roles and provider links of a migrated user'
);

DELETE FROM v_users_active WHERE id = 9700;

-- Test 24: an archived, never-migrated, SSO-only account.
SELECT results_eq(
    $$SELECT enabled, has_local_password, roles, identities
      FROM v_users_sso_export WHERE id = 9700$$,
    $$VALUES (FALSE, FALSE, ARRAY['Guest']::varchar[], '{}'::jsonb)$$,
    'The export flags archived users as disabled and unmigrated users with no identity'
);

SELECT * FROM finish();
ROLLBACK;
