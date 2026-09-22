BEGIN;
SELECT plan(29);

-- Per-API Postgres roles (MAIR-114): security/api_roles.sql and
-- security/api_grants.sql. The migration is run with -D<role>_password in
-- docker-compose-test.yml, so every role has a password.

-- Runs `p_sql` as `p_role` and returns 'ok' or the SQLSTATE it raised.
-- pgTAP assertions stay outside of it: they need the superuser's temp tables.
CREATE FUNCTION pg_temp.run_as(p_role TEXT, p_sql TEXT) RETURNS TEXT AS $$
DECLARE
    v_result TEXT := 'ok';
BEGIN
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_result := SQLSTATE;
    END;
    RESET ROLE;
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Relations of `public` a role can write to (INSERT, UPDATE or DELETE).
CREATE FUNCTION pg_temp.writable_by(p_role TEXT) RETURNS SETOF TEXT AS $$
    SELECT c.relname::TEXT
    FROM pg_class c
    WHERE c.relnamespace = 'public'::regnamespace
      AND c.relkind IN ('r', 'p', 'v')
      AND has_table_privilege(p_role, c.oid, 'INSERT, UPDATE, DELETE')
    ORDER BY 1;
$$ LANGUAGE sql;

---
--- 1. ROLES
---

-- Test 1: the five roles exist, can log in and have no elevated attribute
SELECT is(
    (SELECT count(*)::INT FROM pg_roles
     WHERE rolname IN ('core_api', 'project_api', 'calendar_api', 'message_api', 'elearning_api')
       AND rolcanlogin
       AND NOT rolsuper AND NOT rolcreaterole AND NOT rolcreatedb
       AND NOT rolreplication AND NOT rolbypassrls),
    5,
    'Each API has a login role without elevated attributes'
);

-- Test 2: the -D<role>_password parameters were applied
SELECT is(
    (SELECT count(*)::INT FROM pg_authid
     WHERE rolname IN ('core_api', 'project_api', 'calendar_api', 'message_api', 'elearning_api')
       AND rolpassword LIKE 'SCRAM-SHA-256$%'),
    5,
    'Each API role has a hashed password'
);

---
--- 2. PRIVILEGE MATRIX
---

-- Test 3: logs, audit and Liquibase tables are out of reach of every API
SELECT is(
    (SELECT count(*)::INT
     FROM unnest(ARRAY['core_api', 'project_api', 'calendar_api', 'message_api', 'elearning_api']) AS r(name)
     CROSS JOIN unnest(ARRAY['users_audit_log', 'connection_logs', 'access_logs', 'retention_policies',
                             'databasechangelog', 'databasechangeloglock']) AS t(name)
     WHERE has_table_privilege(r.name, t.name, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')),
    0,
    'No API role has any privilege on log, audit or Liquibase tables'
);

-- Test 4: only core_api can read password hashes
SELECT results_eq(
    $$
    SELECT r.name FROM unnest(ARRAY['core_api', 'project_api', 'calendar_api', 'message_api', 'elearning_api']) AS r(name)
    WHERE has_column_privilege(r.name, 'users', 'password', 'SELECT')
    $$,
    $$VALUES ('core_api')$$,
    'Only core_api can read users.password'
);

-- Test 5: users are never hard-deleted, not even by core_api
SELECT is(
    (SELECT count(*)::INT
     FROM unnest(ARRAY['core_api', 'project_api', 'calendar_api', 'message_api', 'elearning_api']) AS r(name)
     WHERE has_table_privilege(r.name, 'users', 'DELETE, TRUNCATE')),
    0,
    'No API role can hard-delete users'
);

-- Test 6: no API role can create objects
SELECT is(
    (SELECT count(*)::INT
     FROM unnest(ARRAY['core_api', 'project_api', 'calendar_api', 'message_api', 'elearning_api']) AS r(name)
     WHERE has_schema_privilege(r.name, 'public', 'CREATE')),
    0,
    'No API role has CREATE on schema public'
);

-- Tests 7-11: each API writes only to its own domain
SELECT results_eq(
    $$SELECT * FROM pg_temp.writable_by('core_api')$$,
    $$VALUES ('access_control'), ('group_members'), ('groups'), ('roles'), ('sessions'),
             ('user_notification_settings'), ('user_preferences'), ('user_roles'), ('users'),
             ('v_users_active')$$,
    'core_api writes only to the core domain'
);
SELECT results_eq(
    $$SELECT * FROM pg_temp.writable_by('project_api')$$,
    $$VALUES ('project_members'), ('projects'), ('task_assignees'), ('task_history'), ('tasks')$$,
    'project_api writes only to the project domain'
);
SELECT results_eq(
    $$SELECT * FROM pg_temp.writable_by('calendar_api')$$,
    $$VALUES ('event_members'), ('events'), ('recurrence_members'), ('recurrence_rules'),
             ('user_calendar_params')$$,
    'calendar_api writes only to the calendar domain'
);
SELECT results_eq(
    $$SELECT * FROM pg_temp.writable_by('message_api')$$,
    $$VALUES ('conversation_members'), ('conversations'), ('message_business_links'),
             ('message_mentions'), ('messages'), ('unread_counters')$$,
    'message_api writes only to the messaging domain'
);
SELECT results_eq(
    $$SELECT * FROM pg_temp.writable_by('elearning_api')$$,
    $$VALUES ('course_attachments'), ('course_modules'), ('course_ratings'), ('courses'),
             ('user_content_progress'), ('user_courses'), ('user_modules')$$,
    'elearning_api writes only to the e-learning domain'
);

---
--- 3. SEED
---

INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (2000, 'Paul', 'Owner', 'paul.owner@roles.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (2001, 'Lea', 'Member', 'lea.member@roles.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');

INSERT INTO groups (id, name, owner_id) VALUES (2000, 'Roles test group', 2000);
INSERT INTO group_members (group_id, user_id) VALUES (2000, 2001);

INSERT INTO projects (id, title, owner_id) VALUES (2000, 'Roles test project', 2000);
INSERT INTO project_members (project_id, user_id) VALUES (2000, 2001);
INSERT INTO tasks (id, project_id, title, assigned_to) VALUES (2000, 2000, 'Roles test task', 2001);

INSERT INTO conversations (id, title, group_id, kind) VALUES (2000, 'Roles test chat', 2000, 'group');

INSERT INTO courses (id, title) VALUES (2000, 'Roles test course');
INSERT INTO course_modules (id, course_id, title, sort_order) VALUES (2000, 2000, 'Only module', 1);

---
--- 4. CORE_API
---

-- Test 12: login writes connection_logs through a SECURITY DEFINER trigger
SELECT is(
    pg_temp.run_as('core_api',
        $$INSERT INTO sessions (user_id, token_hash) VALUES (2001, 'roles-test-token')$$),
    'ok',
    'core_api can open a session (connection log written by the trigger)'
);

-- Test 13: archiving cleans other domains through SECURITY DEFINER triggers
SELECT is(
    pg_temp.run_as('core_api', $$UPDATE users SET is_archived = TRUE WHERE id = 2001$$),
    'ok',
    'core_api can archive a user who belongs to a project'
);

-- Test 14
SELECT is(
    (SELECT count(*)::INT FROM project_members WHERE user_id = 2001)
        + (SELECT count(*)::INT FROM tasks WHERE assigned_to = 2001),
    0,
    'Archiving by core_api removed project memberships and task assignments'
);

-- Test 15
SELECT is(
    pg_temp.run_as('core_api', $$SELECT title FROM projects$$),
    '42501',
    'core_api cannot read projects'
);

-- Test 16: ownership check before granting an ACL on an event
SELECT is(
    pg_temp.run_as('core_api', $$SELECT EXISTS(SELECT 1 FROM events WHERE id = 1 AND owner_id = 1)$$),
    'ok',
    'core_api can check event ownership'
);

---
--- 5. PROJECT_API
---

-- Test 17
SELECT is(
    pg_temp.run_as('project_api', $$SELECT password FROM users$$),
    '42501',
    'project_api cannot read password hashes'
);

-- Test 18: task_history is written by the status trigger
SELECT is(
    pg_temp.run_as('project_api', $$UPDATE tasks SET status = 'in_progress' WHERE id = 2000$$),
    'ok',
    'project_api can change a task status'
);

-- Test 19
SELECT is(
    pg_temp.run_as('project_api', $$SELECT content FROM messages$$),
    '42501',
    'project_api cannot read messages'
);

---
--- 6. CALENDAR_API
---

-- Test 20: group events get their ACL through a SECURITY DEFINER trigger
SELECT is(
    pg_temp.run_as('calendar_api',
        $$INSERT INTO events (name, start_date, end_date, owner_group_id, created_by)
          VALUES ('Roles test event', '2030-01-01 09:00+00', '2030-01-01 10:00+00', 2000, 2000)$$),
    'ok',
    'calendar_api can create a group event'
);

-- Test 21
SELECT ok(
    EXISTS (
        SELECT 1 FROM access_control ac
        JOIN events e ON e.id = ac.resource_instance_id
        WHERE e.name = 'Roles test event' AND ac.group_id = 2000
    ),
    'The group event ACL was written on behalf of calendar_api'
);

---
--- 7. MESSAGE_API
---

-- Test 22: the unread counter trigger reads group_members
SELECT is(
    pg_temp.run_as('message_api',
        $$INSERT INTO messages (conversation_id, owner_id, content) VALUES (2000, 2000, 'Hello')$$),
    'ok',
    'message_api can post in a group conversation'
);

-- Test 23 (user 2001 was archived above but is still a group member)
SELECT is(
    (SELECT unread_count FROM unread_counters WHERE conversation_id = 2000 AND user_id = 2001),
    1,
    'The other group member got an unread counter'
);

-- Test 24
SELECT is(
    pg_temp.run_as('message_api', $$SELECT id FROM users WHERE id = 2000$$),
    'ok',
    'message_api can check that a user exists (JWT middleware)'
);

-- Test 25
SELECT is(
    pg_temp.run_as('message_api', $$SELECT email FROM users$$),
    '42501',
    'message_api cannot read user details'
);

---
--- 8. ELEARNING_API
---

-- Test 26: the progress trigger updates user_courses
SELECT is(
    pg_temp.run_as('elearning_api',
        $$INSERT INTO user_modules (user_id, module_id, is_completed) VALUES (2000, 2000, TRUE)$$),
    'ok',
    'elearning_api can complete a module'
);

-- Test 27
SELECT is(
    (SELECT status::TEXT FROM user_courses WHERE user_id = 2000 AND course_id = 2000),
    'completed',
    'Completing the only module completed the course'
);

-- Test 28
SELECT is(
    pg_temp.run_as('elearning_api',
        $$INSERT INTO events (name, start_date, end_date, owner_id)
          VALUES ('Forbidden', '2030-01-01 09:00+00', '2030-01-01 10:00+00', 2000)$$),
    '42501',
    'elearning_api cannot create events'
);

---
--- 9. SHARED
---

-- Test 29: check_access and is_admin work for every API
SELECT is(
    (SELECT count(*)::INT
     FROM unnest(ARRAY['core_api', 'project_api', 'calendar_api', 'message_api', 'elearning_api']) AS r(name)
     WHERE pg_temp.run_as(r.name, $$SELECT check_access(2000, 'groups', 'read', 2000), is_admin(2000)$$) = 'ok'),
    5,
    'Every API role can call check_access and is_admin'
);

SELECT * FROM finish();
ROLLBACK;
