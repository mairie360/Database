-- Checks the database produced by run.sh: baseline release + seed.sql, then
-- HEAD applied on top of it (MAIR-413).
BEGIN;
SELECT plan(38);

---
--- Admin account
---
-- Test 1-2: the template account was replaced by the supplied credentials and
-- must change its password on first login.
SELECT results_eq(
    $$SELECT email::TEXT, password::TEXT, first_connect FROM users WHERE id = 1$$,
    $$VALUES ('mayor@upgrade.example',
              '$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              TRUE)$$,
    'The template admin account is replaced by the supplied credentials'
);

SELECT is(
    (SELECT count(*)::INT FROM users WHERE email IN ('template.email@gmail.com', 'admin@example.invalid')),
    0,
    'No template admin account is left'
);

-- Test 3
SELECT ok(is_admin(1), 'The admin account keeps the Admin role');

---
--- Data preserved
---
-- Test 4-12
SELECT is((SELECT count(*)::INT FROM users WHERE id BETWEEN 100 AND 199), 5, 'Users are preserved');
SELECT is((SELECT count(*)::INT FROM user_roles WHERE user_id BETWEEN 100 AND 199 AND role_id <> 5), 4, 'Role assignments are preserved');
SELECT is((SELECT count(*)::INT FROM group_members WHERE group_id = 100), 2, 'Group members are preserved');
SELECT is((SELECT count(*)::INT FROM tasks WHERE project_id = 100), 2, 'Tasks are preserved');
SELECT is((SELECT count(*)::INT FROM events WHERE id = 100), 1, 'Events are preserved');
-- MAIR-481 (rel-1.12.0-01, releases/v3.0.0): rows outside 1970-01-01 - 3000-01-01 are deleted,
-- with their members; valid events and rules stay.
SELECT is(
    (SELECT array_agg(id ORDER BY id) FROM events WHERE id BETWEEN 100 AND 199),
    ARRAY[100, 104],
    'Events outside the date window, or along a rule outside it, are deleted'
);
SELECT is(
    (SELECT array_agg(id ORDER BY id) FROM recurrence_rules WHERE id IN (100, 101)),
    ARRAY[101],
    'Recurrence rules outside the date window are deleted'
);
SELECT is((SELECT count(*)::INT FROM event_members WHERE event_id = 101), 0, 'Members of a deleted event are deleted');
SELECT ok(
    (SELECT bool_and(convalidated) FROM pg_constraint
     WHERE conname IN ('chk_events_date_window', 'chk_recurrence_date_window')),
    'The date window constraints are validated'
);
SELECT is(
    (SELECT count(*)::INT FROM pg_constraint
     WHERE conname IN ('chk_events_date_window', 'chk_recurrence_date_window')),
    2,
    'Both date window constraints exist'
);
SELECT is((SELECT count(*)::INT FROM messages WHERE conversation_id IN (100, 101)), 3, 'Messages are preserved');
SELECT is((SELECT count(*)::INT FROM course_attachments WHERE module_id = 100), 1, 'Course attachments are preserved');
SELECT is((SELECT count(*)::INT FROM access_logs WHERE user_id IN (100, 101)), 2, 'Access logs are preserved');
SELECT is((SELECT password::TEXT FROM users WHERE id = 105), 'plaintext-legacy', 'A legacy plaintext password is kept for migrate_legacy_password');

---
--- Releases applied on existing data
---
-- Test 13: rel-1.6.0-01 (releases/v2.0.0) validates every constraint but the
-- password one while a plaintext password remains.
SELECT is(
    (SELECT string_agg(conname::TEXT, ', ') FROM pg_constraint
     WHERE connamespace = 'public'::regnamespace AND NOT convalidated),
    'chk_users_password_hashed',
    'Only chk_users_password_hashed stays NOT VALID'
);

-- Test 14: rel-1.6.0-01 moved this month's access logs out of the DEFAULT
-- partition (older months stay there by design).
SELECT is(
    (SELECT count(*)::INT FROM access_logs_default WHERE timestamp >= date_trunc('month', now())),
    0,
    'Current-month access logs are in their monthly partition'
);

-- Test 15: rel-1.7.0-01 (releases/v2.0.0)
SELECT ok(
    EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'users' AND indexname = 'uq_users_email_lower'),
    'The case-insensitive e-mail index exists'
);


-- Test 16-20: rel-1.8.0-* (releases/v2.0.0) on existing data (MAIR-392/393/394).
SELECT is(
    (SELECT approval_status::TEXT FROM events WHERE id = 100),
    'pending',
    'An event with a pending member is pending'
);

SELECT results_eq(
    $$SELECT author_id, message FROM task_comments WHERE task_id = 101$$,
    $$VALUES (100, 'Barriers ordered'::TEXT)$$,
    'Legacy task comments are migrated once'
);

SELECT results_eq(
    $$SELECT changed_by, action::TEXT, label FROM task_history WHERE task_id = 101 AND label IS NOT NULL$$,
    $$VALUES (101, 'task_updated', 'Title changed'::TEXT)$$,
    'Legacy task history is migrated once'
);

SELECT is(
    (SELECT custom_fields FROM tasks WHERE id = 101),
    '{"fields": [{"label": "Budget"}]}'::JSONB,
    'Legacy comments and history are stripped from custom_fields'
);

SELECT is(
    (SELECT created_by FROM conversations WHERE id = 101),
    100,
    'A conversation creator is backfilled with its earliest member'
);


-- Test 21-25: rel-1.9.0-* (releases/v3.0.0) on existing data (MAIR-478). run.sh
-- rolled releases/v3.0.0 back and applied it again.
SELECT results_eq(
    $$SELECT id, kind::TEXT, direct_user_low, direct_user_high
      FROM conversations WHERE id BETWEEN 100 AND 199 ORDER BY id$$,
    $$VALUES (100, 'group', NULL::INT, NULL::INT),
             (101, 'direct', 100, 102),
             (102, 'direct', 100, 101),
             (104, 'direct', 101, 102),
             (105, 'group', NULL, NULL),
             (106, 'group', NULL, NULL)$$,
    'Only the chats of exactly two agents stay direct, duplicates merged into the oldest one'
);

SELECT results_eq(
    $$SELECT content FROM messages WHERE conversation_id = 102 ORDER BY id$$,
    $$VALUES ('Hi Alice'::TEXT), ('Are you there?')$$,
    'The messages of a duplicate move to the merged chat'
);

SELECT results_eq(
    $$SELECT user_id, is_excluded FROM conversation_members WHERE conversation_id = 102 ORDER BY user_id$$,
    $$VALUES (100, FALSE), (101, FALSE)$$,
    'A participant sees the merged chat when they saw one of its copies'
);

SELECT results_eq(
    $$SELECT user_id, is_excluded FROM conversation_members WHERE conversation_id = 104 ORDER BY user_id$$,
    $$VALUES (101, FALSE), (102, TRUE)$$,
    'A participant who left a direct chat gets a hidden membership back'
);

SELECT is(
    (SELECT unread_count FROM unread_counters WHERE conversation_id = 102 AND user_id = 100),
    2,
    'Unread counters of the duplicates add up'
);


-- Test 26-27: rel-1.10.0-01 (releases/v3.0.0) on existing data (MAIR-480). run.sh
-- rolled it back (trunk prefix restored, country dropped) and applied it again.
SELECT results_eq(
    $$SELECT id, phone_country::TEXT, phone_number::TEXT FROM users WHERE id BETWEEN 100 AND 103 ORDER BY id$$,
    $$VALUES (100, 'FR', '612345678'), (101, 'RE', '692123456'), (102, 'FR', '145678901'), (103, NULL, NULL)$$,
    'Legacy phone numbers are split into country and national number'
);

SELECT ok(
    EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_phone' AND convalidated),
    'chk_users_phone is validated'
);


---
--- Release tags
---
-- The database carries one tag per git tag, each one set right before the
-- first changeset of the next tag: the baseline gets v1.3.0 although its
-- changelog had no tag.
SELECT results_eq(
    $$SELECT tag FROM databasechangelog WHERE tag IS NOT NULL ORDER BY orderexecuted$$,
    $$VALUES ('v1.3.0'::VARCHAR), ('v2.0.0'), ('v3.0.0'), ('v3.1.0')$$,
    'The database is tagged with the git tags, in order'
);

SELECT ok(
    (SELECT orderexecuted FROM databasechangelog WHERE tag = 'v1.3.0')
        < (SELECT orderexecuted FROM databasechangelog WHERE id = 'rel-1.3.0-01')
    AND (SELECT orderexecuted FROM databasechangelog WHERE tag = 'v2.0.0')
        < (SELECT orderexecuted FROM databasechangelog WHERE id = 'rel-1.9.0-01'),
    'Each tag is set before the changesets of the next git tag'
);

---
--- Archived accounts and privileges
---
-- Test 30-31: archived before the upgrade, the admin keeps its role row but
-- loses its rights.
SELECT ok(
    EXISTS (SELECT 1 FROM user_roles WHERE user_id = 103 AND role_id = 1) AND NOT is_admin(103),
    'An archived admin keeps its role row but is not admin'
);

SELECT is(check_access(103, 'groups', 'delete', 100), 0, 'An archived admin is denied by check_access');

-- Test 32-33: the runAlways grants are applied on the existing database.
SELECT ok(
    has_table_privilege('core_api', 'users', 'SELECT')
    AND has_function_privilege('core_api', 'check_access(integer, character varying, character varying, integer)', 'EXECUTE'),
    'API roles get their privileges back on the upgraded database'
);

SELECT ok(
    NOT has_function_privilege('public', 'check_access(integer, character varying, character varying, integer)', 'EXECUTE'),
    'PUBLIC cannot call check_access on the upgraded database'
);

SELECT * FROM finish();
ROLLBACK;
