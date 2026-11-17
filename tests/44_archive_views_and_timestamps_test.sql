-- MAIR-535: objects no other file asserts by name.
--   * v_users_active / v_users_archived split on is_archived;
--   * restore_user() on an id that is not archived or does not exist;
--   * fn_check_can_delete_user(): the events-owner and projects-owner branches;
--   * users_audit_log: UPDATE refused (fn_protect_audit_log), RESTORE row written
--     by fn_audit_and_mutate_user;
--   * fn_set_group_accesses / trigger_set_group_accesses on events with an owner group;
--   * v_securable_events and v_securable_sessions inject the resource id;
--   * fn_refresh_updated_at (users.updated_at is rewritten on every UPDATE).
BEGIN;
SELECT plan(21);

INSERT INTO users (id, first_name, last_name, email, password, status)
VALUES
    (4401, 'Arch', 'Ived', 'mair535.archived@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active'),
    (4402, 'Act', 'Ive', 'mair535.active@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active'),
    (4403, 'Event', 'Owner', 'mair535.events@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active'),
    (4404, 'Project', 'Owner', 'mair535.projects@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active');

---
--- v_users_active / v_users_archived
---
UPDATE users SET is_archived = TRUE, status = 'archived' WHERE id = 4401;

SELECT is(
    (SELECT count(*)::INT FROM v_users_active WHERE id = 4401),
    0,
    'An archived user is absent from v_users_active'
);
SELECT is(
    (SELECT count(*)::INT FROM v_users_archived WHERE id = 4401),
    1,
    'An archived user is present in v_users_archived'
);
SELECT is(
    (SELECT count(*)::INT FROM v_users_archived WHERE id = 4402),
    0,
    'An active user is absent from v_users_archived'
);
SELECT is(
    (SELECT count(*)::INT FROM v_users_active WHERE id = 4402),
    1,
    'An active user is present in v_users_active'
);

---
--- restore_user(): RESTORE audit row, then the no-op cases
---
SELECT restore_user(4401);

SELECT is(
    (SELECT count(*)::INT FROM users_audit_log WHERE user_id = 4401 AND action_type = 'RESTORE'),
    1,
    'restore_user writes exactly one RESTORE row in users_audit_log'
);
SELECT is(
    (SELECT count(*)::INT FROM v_users_archived WHERE id = 4401),
    0,
    'A restored user leaves v_users_archived'
);

SELECT lives_ok(
    $$ SELECT restore_user(4402) $$,
    'restore_user on a user that is not archived is a no-op, not an error'
);
SELECT is(
    (SELECT status::TEXT FROM users WHERE id = 4402),
    'active',
    'restore_user leaves a user that is not archived untouched (status stays active)'
);
SELECT lives_ok(
    $$ SELECT restore_user(999999) $$,
    'restore_user on an unknown id is a no-op, not an error'
);
SELECT is(
    (SELECT count(*)::INT FROM users WHERE id = 999999),
    0,
    'restore_user does not create the unknown user'
);

---
--- fn_check_can_delete_user(): events-owner and projects-owner branches
---
INSERT INTO events (name, start_date, end_date, created_by, owner_id)
VALUES ('MAIR-535 owned event', '2026-06-01 10:00:00', '2026-06-01 11:00:00', 4403, 4403);
INSERT INTO projects (id, title, owner_id) VALUES (44041, 'MAIR-535 owned project', 4404);

SELECT throws_ok(
    $$ UPDATE users SET is_archived = TRUE, status = 'archived' WHERE id = 4403 $$,
    '23001',
    'Utilisateur 4403 est propriétaire d''événements.',
    'A user who still owns an event cannot be archived'
);
SELECT throws_ok(
    $$ UPDATE users SET is_archived = TRUE, status = 'archived' WHERE id = 4404 $$,
    '23001',
    'Utilisateur 4404 est propriétaire de projets.',
    'A user who still owns a project cannot be archived'
);

---
--- users_audit_log is append-only
---
SELECT throws_ok(
    $$ UPDATE users_audit_log SET reason = 'tampered' WHERE user_id = 4401 $$,
    'P0001',
    'users_audit_log is append-only',
    'An UPDATE of users_audit_log is refused'
);

---
--- fn_set_group_accesses: an event owned by a group grants its ACL to that group
---
INSERT INTO groups (id, owner_id, name, description) VALUES (4410, 4402, 'MAIR-535 group', 'owner group of an event');
INSERT INTO events (id, name, start_date, end_date, created_by, owner_group_id)
VALUES (44100, 'MAIR-535 group event', '2026-06-02 10:00:00', '2026-06-02 11:00:00', 4402, 4410);

SELECT is(
    (SELECT array_agg(p.action::TEXT ORDER BY p.action)
       FROM access_control ac
       JOIN permissions p ON p.id = ac.permission_id
      WHERE ac.group_id = 4410
        AND ac.resource_instance_id = 44100
        AND ac.resource_id = (SELECT id FROM resources WHERE name = 'events')
        AND p.action IN ('read', 'update', 'delete')),
    ARRAY['delete', 'read', 'update'],
    'An event with an owner group gives that group read, update and delete on it'
);
SELECT is(
    (SELECT count(*)::INT FROM access_control WHERE resource_instance_id = 44100 AND group_id IS DISTINCT FROM 4410),
    0,
    'The ACL of a group-owned event is written for the owner group only'
);
SELECT is(
    (SELECT count(*)::INT FROM access_control ac JOIN permissions p ON p.id = ac.permission_id
      WHERE ac.resource_instance_id = 44100
        AND ac.resource_id = (SELECT id FROM resources WHERE name = 'events')
        AND p.resource_id <> ac.resource_id),
    0,
    'No ACL row of a group-owned event pairs the events resource with a permission of another resource'
);

-- Release v3.4.1 purge: a row left by the former trigger (events resource + permission of another resource) goes away,
-- the correct rows stay. The statement is the one of releases/v3.4.1/01__purge_misattributed_event_acl.sql.
INSERT INTO access_control (group_id, resource_id, resource_instance_id, permission_id)
SELECT 4410, res.id, 44100, p.id
FROM resources res, permissions p
WHERE res.name = 'events' AND p.resource_id <> res.id AND p.action = 'read'
LIMIT 1;
INSERT INTO groups (id, owner_id, name, description) VALUES (4411, 4402, 'MAIR-535 other group', 'does not own the event');
-- Decoys the purge must keep: same shape but a group that does not own the event, and an instance that is no event.
INSERT INTO access_control (group_id, resource_id, resource_instance_id, permission_id)
SELECT 4411, res.id, 44100, p.id
FROM resources res, permissions p
WHERE res.name = 'events' AND p.resource_id <> res.id AND p.action = 'read'
LIMIT 1;
INSERT INTO access_control (group_id, resource_id, resource_instance_id, permission_id)
SELECT 4410, res.id, 99999999, p.id
FROM resources res, permissions p
WHERE res.name = 'events' AND p.resource_id <> res.id AND p.action = 'read'
LIMIT 1;
DELETE FROM access_control ac
USING permissions p, resources res, events e
WHERE p.id = ac.permission_id
  AND res.id = ac.resource_id
  AND res.name = 'events'
  AND e.id = ac.resource_instance_id
  AND e.owner_group_id = ac.group_id
  AND p.action IN ('read', 'update', 'delete')
  AND p.resource_id <> ac.resource_id;
SELECT is(
    (SELECT count(*)::INT FROM access_control WHERE resource_instance_id = 44100),
    4,
    'The v3.4.1 purge removes the misattributed ACL rows and keeps the 3 correct ones plus the row of another group'
);
SELECT is(
    (SELECT count(*)::INT FROM access_control WHERE resource_instance_id = 99999999),
    1,
    'The v3.4.1 purge keeps a row whose instance is not an event'
);

---
--- Securable views inject the resource id
---
SELECT is(
    (SELECT resource_id FROM v_securable_events WHERE id = 44100),
    (SELECT id FROM resources WHERE name = 'events'),
    'v_securable_events injects the events resource id'
);

INSERT INTO sessions (user_id, token_hash, device_info) VALUES (4402, 'mair535_token', 'Firefox/Linux');
SELECT is(
    (SELECT resource_id FROM v_securable_sessions WHERE token_hash = 'mair535_token'),
    (SELECT id FROM resources WHERE name = 'sessions'),
    'v_securable_sessions injects the sessions resource id'
);

---
--- fn_refresh_updated_at
---
UPDATE users SET last_name = 'Touched', updated_at = '2000-01-01 00:00:00+00' WHERE id = 4402;
SELECT is(
    (SELECT updated_at FROM users WHERE id = 4402),
    now(),
    'fn_refresh_updated_at rewrites users.updated_at on every UPDATE'
);

SELECT * FROM finish();
ROLLBACK;
