BEGIN;
SELECT plan(10);

-- MAIR-502 (releases/v3.1.0): a completed task is archived (tasks.archived_at), kept by
-- the trigger tr_before_task_archive.

-- Plan of `p_sql`, one line per row of EXPLAIN, joined.
CREATE FUNCTION pg_temp.plan_of(p_sql TEXT) RETURNS TEXT AS $$
DECLARE
    v_line TEXT;
    v_plan TEXT := '';
BEGIN
    FOR v_line IN EXECUTE 'EXPLAIN (COSTS OFF) ' || p_sql LOOP
        v_plan := v_plan || v_line || E'\n';
    END LOOP;
    RETURN v_plan;
END;
$$ LANGUAGE plpgsql;

INSERT INTO users (id, first_name, last_name, email, password, status, is_archived)
VALUES (95020, 'Archive', 'Owner', 'archive.owner@example.com',
        '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active', FALSE);
INSERT INTO projects (id, title, owner_id) VALUES (95020, 'Archived tasks project', 95020);
INSERT INTO tasks (id, project_id, title, status) VALUES
    (95021, 95020, 'Open task', 'todo'),
    (95022, 95020, 'Done from the start', 'completed');

SELECT is(
    (SELECT archived_at FROM tasks WHERE id = 95021), NULL,
    'An open task is active'
);
SELECT isnt(
    (SELECT archived_at FROM tasks WHERE id = 95022), NULL,
    'A task created completed is archived at once'
);

UPDATE tasks SET status = 'completed' WHERE id = 95021;
SELECT isnt(
    (SELECT archived_at FROM tasks WHERE id = 95021), NULL,
    'A task becoming completed is archived'
);

-- An edit of an archived task keeps its archive date.
UPDATE tasks SET archived_at = TIMESTAMP '2026-01-01 08:00:00' WHERE id = 95021;
UPDATE tasks SET title = 'Renamed while archived' WHERE id = 95021;
SELECT is(
    (SELECT archived_at FROM tasks WHERE id = 95021), TIMESTAMP '2026-01-01 08:00:00',
    'Editing a completed task keeps its archive date'
);

UPDATE tasks SET status = 'in_progress' WHERE id = 95021;
SELECT is(
    (SELECT archived_at FROM tasks WHERE id = 95021), NULL,
    'A reopened task is active again'
);

-- A client cannot archive an open task by writing the column.
UPDATE tasks SET archived_at = CURRENT_TIMESTAMP WHERE id = 95021;
SELECT is(
    (SELECT archived_at FROM tasks WHERE id = 95021), NULL,
    'Only the trigger archives: an open task stays active'
);

SELECT has_index(
    'tasks', 'idx_tasks_project_active', ARRAY['project_id', 'created_at', 'id'],
    'Partial index of the active tasks of a project, in list order'
);
SELECT has_index(
    'tasks', 'idx_tasks_project_archived', ARRAY['project_id', 'archived_at', 'id'],
    'Partial index of the archived tasks of a project'
);

-- The two lists of Project_API read their partial index. Sequential scans are disabled so the
-- plan does not depend on the size of the test data.
SET LOCAL enable_seqscan = off;
SELECT alike(
    pg_temp.plan_of($$
        SELECT id FROM tasks WHERE project_id = 95020 AND archived_at IS NULL
        ORDER BY created_at, id LIMIT 100
    $$),
    '%idx_tasks_project_active%',
    'The active tasks of a project are read through idx_tasks_project_active'
);
SELECT alike(
    pg_temp.plan_of($$
        SELECT id FROM tasks WHERE project_id = 95020 AND archived_at IS NOT NULL
        ORDER BY archived_at DESC, id DESC LIMIT 100
    $$),
    '%idx_tasks_project_archived%',
    'The archived tasks of a project are read through idx_tasks_project_archived'
);

SELECT * FROM finish();
ROLLBACK;
