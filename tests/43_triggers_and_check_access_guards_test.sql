-- MAIR-239: guards and session triggers that no other file asserts by name.
--   * check_access(): a declared resource without a table, and the user_id
--     ownership fallback for a table that has no owner_id;
--   * fn_block_global_in_acl(): a global (_all) permission is refused in access_control;
--   * check_policy_safety(): PARTITION_DROP is refused on critical tables;
--   * log_session_start / log_session_refresh / log_session_end /
--     fn_handle_session_deletion: one connection_logs row per session event.
BEGIN;
SELECT plan(13);

INSERT INTO users (id, first_name, last_name, email, password, status)
VALUES
    (4301, 'Owner', 'Guard', 'mair239.owner@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active'),
    (4302, 'Other', 'Guard', 'mair239.other@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active');

---
--- check_access()
---

-- A resource declared in `resources` whose table does not exist
INSERT INTO resources (name) VALUES ('mair239_ghost');
SELECT is(
    check_access(4301, 'mair239_ghost', 'read', 1),
    -1,
    'check_access answers -1 for a declared resource that has no table'
);

-- A table with user_id but no owner_id: ownership goes through user_id
CREATE TABLE public.mair239_notes (id INT PRIMARY KEY, user_id INT NOT NULL);
INSERT INTO mair239_notes (id, user_id) VALUES (1, 4301);
INSERT INTO resources (name) VALUES ('mair239_notes');

SELECT is(
    check_access(4301, 'mair239_notes', 'read', 1),
    1,
    'check_access grants the owner found through user_id when the table has no owner_id'
);
SELECT is(
    check_access(4302, 'mair239_notes', 'read', 1),
    0,
    'check_access denies another user on that table'
);

---
--- fn_block_global_in_acl()
---

INSERT INTO permissions (resource_id, action)
SELECT id, a FROM resources, unnest(ARRAY['read', 'read_all']) AS a
WHERE name = 'mair239_notes';

SELECT lives_ok(
    $$ INSERT INTO access_control (user_id, resource_id, resource_instance_id, permission_id)
       SELECT 4302, r.id, 1, p.id FROM resources r JOIN permissions p ON p.resource_id = r.id
       WHERE r.name = 'mair239_notes' AND p.action = 'read' $$,
    'An ACL entry with an instance permission is accepted'
);
SELECT throws_ok(
    $$ INSERT INTO access_control (user_id, resource_id, resource_instance_id, permission_id)
       SELECT 4301, r.id, 1, p.id FROM resources r JOIN permissions p ON p.resource_id = r.id
       WHERE r.name = 'mair239_notes' AND p.action = 'read_all' $$,
    'P0001',
    NULL,
    'An ACL entry cannot carry a global (_all) permission'
);
SELECT throws_ok(
    $$ UPDATE access_control SET permission_id = (SELECT id FROM permissions WHERE action = 'read_all'
                                                   AND resource_id = access_control.resource_id)
       WHERE user_id = 4302 AND resource_instance_id = 1 $$,
    'P0001',
    NULL,
    'An ACL entry cannot be switched to a global (_all) permission'
);

---
--- check_policy_safety()
---

SELECT throws_ok(
    $$ UPDATE retention_policies SET strategy = 'PARTITION_DROP' WHERE table_name = 'users' $$,
    'P0001',
    NULL,
    'PARTITION_DROP is refused on the critical table users'
);
SELECT lives_ok(
    $$ INSERT INTO retention_policies (table_name, retention_period, strategy)
       VALUES ('mair239_notes', '1 year', 'PARTITION_DROP') $$,
    'PARTITION_DROP is accepted on a table that is not critical'
);

---
--- session log triggers
---

INSERT INTO sessions (id, user_id, token_hash)
VALUES ('00000000-0000-4000-8000-000000004301', 4301, 'mair239_token_1');

SELECT is(
    (SELECT count(*)::INT FROM connection_logs
     WHERE session_id = '00000000-0000-4000-8000-000000004301' AND action_type = 'LOGIN'),
    1,
    'Creating a session logs one LOGIN'
);

UPDATE sessions SET token_hash = 'mair239_token_2' WHERE id = '00000000-0000-4000-8000-000000004301';
SELECT is(
    (SELECT count(*)::INT FROM connection_logs
     WHERE session_id = '00000000-0000-4000-8000-000000004301' AND action_type = 'REFRESH'),
    1,
    'Changing the token hash logs one REFRESH'
);

UPDATE sessions SET revoked_at = now() WHERE id = '00000000-0000-4000-8000-000000004301';
UPDATE sessions SET revoked_at = now() WHERE id = '00000000-0000-4000-8000-000000004301';
SELECT is(
    (SELECT count(*)::INT FROM connection_logs
     WHERE session_id = '00000000-0000-4000-8000-000000004301' AND action_type = 'LOGOUT'),
    1,
    'Revoking a session logs one LOGOUT, only the first time'
);

DELETE FROM sessions WHERE id = '00000000-0000-4000-8000-000000004301';
SELECT is(
    (SELECT count(*)::INT FROM connection_logs
     WHERE session_id = '00000000-0000-4000-8000-000000004301' AND action_type = 'CLEANUP'),
    1,
    'Deleting a session logs one CLEANUP'
);
SELECT is(
    (SELECT count(*)::INT FROM connection_logs WHERE session_id = '00000000-0000-4000-8000-000000004301'),
    4,
    'The session left exactly LOGIN, REFRESH, LOGOUT and CLEANUP'
);

SELECT * FROM finish();
ROLLBACK;
