BEGIN;
SELECT plan(9);

-- Start date of a task (releases/v4.0.0/04, MAIR-1087): same type as due_date, optional, never
-- after the due date; a change is written to the task history.

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
VALUES (5300, 'Sami', 'Start', 'sami.start@task-start-date.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
INSERT INTO projects (id, title, owner_id) VALUES (5300, 'Town hall works', 5300);
INSERT INTO tasks (id, project_id, title, due_date, updated_by)
VALUES (5300, 5300, 'Scaffolding', '2027-05-31 00:00:00', 5300);

--- 1. STRUCTURE (2 tests)
SELECT col_type_is('tasks', 'start_date',
                   (SELECT format_type(atttypid, atttypmod) FROM pg_attribute
                    WHERE attrelid = 'tasks'::regclass AND attname = 'due_date'),
                   'start_date has the type of due_date');
SELECT col_is_null('tasks', 'start_date', 'the start date is optional');

--- 2. VALUES (5 tests)
SELECT ok((SELECT start_date IS NULL FROM tasks WHERE id = 5300), 'a task starts without start date');
SELECT is(
    pg_temp.run_as('project_api', $$UPDATE tasks SET start_date = '2027-05-01 00:00:00', updated_by = 5300 WHERE id = 5300$$),
    'ok', 'project_api sets a start date before the due date'
);
SELECT lives_ok(
    $$UPDATE tasks SET start_date = due_date WHERE id = 5300$$,
    'a task may start the day it is due'
);
SELECT throws_ok(
    $$UPDATE tasks SET start_date = '2027-06-01 00:00:00' WHERE id = 5300$$,
    '23514', NULL, 'a start date after the due date is refused'
);
SELECT lives_ok(
    $$INSERT INTO tasks (project_id, title, start_date) VALUES (5300, 'Unscheduled end', '2030-01-01 00:00:00')$$,
    'a start date without due date is accepted'
);

--- 3. HISTORY (2 tests)
SELECT is(
    (SELECT changes -> 'start_date' FROM task_history
     WHERE task_id = 5300 AND action = 'task_updated' AND changes ? 'start_date'
     ORDER BY id LIMIT 1),
    '{"from": null, "to": "2027-05-01T00:00:00Z"}'::jsonb,
    'setting the start date is written to the task history'
);
SELECT is(
    (SELECT count(*)::INT FROM task_history WHERE task_id = 5300 AND changes ? 'start_date'),
    2, 'each change of the start date is a history entry'
);

SELECT * FROM finish();
ROLLBACK;
