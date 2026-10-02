BEGIN;
SELECT plan(16);

-- MAIR-393: task description, task_comments and the trigger-only task_history
-- (releases/v1.8.0, repeatable/project/fn_log_task_change.sql).

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

INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (3900, 'Nina', 'Manager', 'nina.manager@history.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (3901, 'Omar', 'Agent', 'omar.agent@history.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
INSERT INTO projects (id, title, owner_id) VALUES (3900, 'History test project', 3900);

---
--- 1. STRUCTURE (3 tests)
---
SELECT has_column('tasks', 'description', 'tasks.description exists');
SELECT has_column('tasks', 'updated_by', 'tasks.updated_by exists');
SELECT has_table('task_comments');

---
--- 2. HISTORY WRITTEN BY THE TRIGGER (7 tests)
---
INSERT INTO tasks (id, project_id, title, description, updated_by, custom_fields)
VALUES (3900, 3900, 'Repaint the town hall', 'Front facade', 3900, '{"fields": []}');

SELECT is(
    (SELECT changed_by FROM task_history WHERE task_id = 3900 AND action = 'task_created'),
    3900,
    'Creating a task logs task_created signed by updated_by'
);

UPDATE tasks SET status = 'in_progress', updated_by = 3901, updated_at = CURRENT_TIMESTAMP WHERE id = 3900;

SELECT results_eq(
    $$SELECT changed_by, old_status::TEXT, new_status::TEXT FROM task_history
      WHERE task_id = 3900 AND action = 'status_changed'$$,
    $$VALUES (3901, 'todo', 'in_progress')$$,
    'A status change logs status_changed signed by updated_by'
);

SELECT is(
    (SELECT count(*)::INT FROM task_history WHERE task_id = 3900 AND action = 'task_updated'),
    0,
    'A status-only change does not log task_updated'
);

UPDATE tasks SET title = 'Repaint the town hall and the school', description = 'Both facades',
    custom_fields = jsonb_set(custom_fields, '{fields}', '[{"label": "Budget"}]'), updated_by = 3900
WHERE id = 3900;

SELECT is(
    (SELECT changes FROM task_history WHERE task_id = 3900 AND action = 'task_updated'),
    '{"title": {"from": "Repaint the town hall", "to": "Repaint the town hall and the school"},
      "description": {"from": "Front facade", "to": "Both facades"},
      "fields": {"from": [], "to": [{"label": "Budget"}]}}'::JSONB,
    'Field changes are logged as one task_updated row with from/to per field'
);

SELECT is(
    (SELECT changed_by FROM task_history WHERE task_id = 3900 AND action = 'task_updated'),
    3900,
    'task_updated is signed by updated_by'
);

UPDATE tasks SET updated_at = CURRENT_TIMESTAMP, updated_by = 3901 WHERE id = 3900;

SELECT is(
    (SELECT count(*)::INT FROM task_history WHERE task_id = 3900),
    3,
    'An update that changes no tracked field logs nothing'
);

UPDATE tasks SET assigned_to = 3901, updated_by = 3900 WHERE id = 3900;
UPDATE users SET is_archived = TRUE WHERE id = 3901;

SELECT results_eq(
    $$SELECT changed_by, changes FROM task_history WHERE task_id = 3900 AND action = 'task_updated'
      ORDER BY id DESC LIMIT 1$$,
    $$VALUES (NULL::INT, '{"assigned_to": {"from": 3901, "to": null}}'::JSONB)$$,
    'Unassigning an archived user is a system write (changed_by NULL)'
);

---
--- 3. HISTORY IS READ-ONLY FOR project_api (3 tests)
---
SELECT is(
    pg_temp.run_as('project_api', $$INSERT INTO task_history (task_id, action) VALUES (3900, 'task_updated')$$),
    '42501',
    'project_api cannot forge a history entry'
);

SELECT is(
    pg_temp.run_as('project_api', $$DELETE FROM task_history WHERE task_id = 3900$$),
    '42501',
    'project_api cannot erase the history'
);

SELECT is(
    pg_temp.run_as('project_api', $$UPDATE tasks SET priority = 'high', updated_by = 3900 WHERE id = 3900$$),
    'ok',
    'project_api still writes the history through the trigger'
);

---
--- 4. COMMENTS (3 tests)
---
SELECT is(
    pg_temp.run_as('project_api',
        $$INSERT INTO task_comments (task_id, author_id, message) VALUES (3900, 3900, 'Scaffolding booked')$$),
    'ok',
    'project_api can add a comment'
);

SELECT throws_ok(
    $$INSERT INTO task_comments (task_id, author_id, message) VALUES (3900, 3900, '   ')$$,
    '23514',
    NULL,
    'A blank comment is refused'
);

SELECT throws_ok(
    $$INSERT INTO task_comments (task_id, author_id, message) VALUES (3900, 3900, repeat('a', 2001))$$,
    '23514',
    NULL,
    'A comment longer than 2000 characters is refused'
);

SELECT * FROM finish();
ROLLBACK;
