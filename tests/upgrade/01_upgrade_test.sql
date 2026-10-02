-- Checks the database produced by run.sh: baseline release + seed.sql, then
-- HEAD applied on top of it (MAIR-413).
BEGIN;
SELECT plan(20);

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
SELECT is((SELECT count(*)::INT FROM messages WHERE conversation_id IN (100, 101)), 3, 'Messages are preserved');
SELECT is((SELECT count(*)::INT FROM course_attachments WHERE module_id = 100), 1, 'Course attachments are preserved');
SELECT is((SELECT count(*)::INT FROM access_logs WHERE user_id IN (100, 101)), 2, 'Access logs are preserved');
SELECT is((SELECT password::TEXT FROM users WHERE id = 105), 'plaintext-legacy', 'A legacy plaintext password is kept for migrate_legacy_password');

---
--- Releases applied on existing data
---
-- Test 13: v1.6.0 validates every constraint but the password one while a
-- plaintext password remains.
SELECT is(
    (SELECT string_agg(conname::TEXT, ', ') FROM pg_constraint
     WHERE connamespace = 'public'::regnamespace AND NOT convalidated),
    'chk_users_password_hashed',
    'Only chk_users_password_hashed stays NOT VALID'
);

-- Test 14: v1.6.0 moved this month's access logs out of the DEFAULT
-- partition (older months stay there by design).
SELECT is(
    (SELECT count(*)::INT FROM access_logs_default WHERE timestamp >= date_trunc('month', now())),
    0,
    'Current-month access logs are in their monthly partition'
);

-- Test 15: v1.7.0
SELECT ok(
    EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'users' AND indexname = 'uq_users_email_lower'),
    'The case-insensitive e-mail index exists'
);

-- Test 16
SELECT ok(
    EXISTS (SELECT 1 FROM databasechangelog WHERE tag = 'v1.7.0'),
    'The database is tagged v1.7.0'
);

---
--- Archived accounts and privileges
---
-- Test 17-18: archived before the upgrade, the admin keeps its role row but
-- loses its rights.
SELECT ok(
    EXISTS (SELECT 1 FROM user_roles WHERE user_id = 103 AND role_id = 1) AND NOT is_admin(103),
    'An archived admin keeps its role row but is not admin'
);

SELECT is(check_access(103, 'groups', 'delete', 100), 0, 'An archived admin is denied by check_access');

-- Test 19-20: the runAlways grants are applied on the existing database.
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
