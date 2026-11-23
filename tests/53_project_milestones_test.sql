BEGIN;
SELECT plan(16);

-- Milestones of a project (releases/v4.0.0/03, MAIR-1086): Project_API writes them, a deleted
-- milestone keeps its row (deleted_at), updated_at follows every write, the authors are user ids
-- without foreign key and are exported with the user's data.

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
VALUES (5200, 'Mila', 'Milestone', 'mila.milestone@project-milestones.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
INSERT INTO projects (id, title, owner_id) VALUES (5200, 'Library extension', 5200), (5201, 'Bike lane', 5200);

--- 1. STRUCTURE (6 tests)
SELECT has_table('project_milestones');
SELECT col_is_pk('project_milestones', 'id');
SELECT col_type_is('project_milestones', 'due_date', 'date', 'a milestone falls on a day');
SELECT col_has_default('project_milestones', 'reached', 'reached has a default (FALSE)');
-- A foreign key to users would make the TRUNCATE users CASCADE of the API test harness empty the
-- milestones (see mair-691-02).
SELECT ok(
    NOT EXISTS (SELECT 1 FROM pg_constraint
                WHERE conrelid = 'project_milestones'::regclass AND contype = 'f'
                  AND confrelid = 'users'::regclass),
    'the authors of a milestone are not foreign keys'
);
SELECT has_index('project_milestones', 'idx_project_milestones_project_due',
                 ARRAY['project_id', 'due_date', 'id'], 'milestones of a project in date order');

--- 2. PRIVILEGES OF project_api (3 tests)
SELECT is(
    pg_temp.run_as('project_api', $$INSERT INTO project_milestones (id, project_id, title, due_date, created_by, updated_by)
                                    VALUES (5200, 5200, 'Building permit', '2027-03-01', 5200, 5200),
                                           (5201, 5200, 'Works start', '2027-06-01', 5200, 5200),
                                           (5202, 5201, 'Survey', '2027-01-15', 5200, 5200)$$),
    'ok', 'project_api creates milestones'
);
SELECT is(
    pg_temp.run_as('project_api', $$UPDATE project_milestones SET reached = TRUE, updated_by = 5200 WHERE id = 5200$$),
    'ok', 'project_api updates a milestone'
);
SELECT is(
    pg_temp.run_as('project_api', $$UPDATE project_milestones SET deleted_at = now() WHERE id = 5201$$),
    'ok', 'project_api soft deletes a milestone'
);

--- 3. CONSTRAINTS AND TRIGGER (5 tests)
SELECT throws_ok(
    $$INSERT INTO project_milestones (project_id, title, due_date) VALUES (5200, '   ', '2027-01-01')$$,
    '23514', NULL, 'a blank title is refused'
);
SELECT throws_ok(
    $$INSERT INTO project_milestones (project_id, title, due_date) VALUES (999999, 'Orphan', '2027-01-01')$$,
    '23503', NULL, 'a milestone of an unknown project is refused'
);
SELECT throws_ok(
    $$INSERT INTO project_milestones (project_id, title) VALUES (5200, 'No date')$$,
    '23502', NULL, 'a milestone has a due date'
);
UPDATE project_milestones SET updated_at = '2000-01-01 00:00:00+00' WHERE id = 5200;
SELECT ok(
    (SELECT updated_at > '2000-01-01 00:00:00+00' FROM project_milestones WHERE id = 5200),
    'updated_at is refreshed on every write'
);
SELECT results_eq(
    $$SELECT id FROM project_milestones WHERE project_id = 5200 AND deleted_at IS NULL ORDER BY due_date, id$$,
    $$VALUES (5200)$$,
    'a soft deleted milestone is left out of the list'
);

--- 4. EXPORT AND PROJECT DELETION (2 tests)
SELECT is(
    jsonb_array_length(export_user_data(5200) -> 'data' -> 'project_milestones.created_by'),
    3, 'the milestones created by the user are exported'
);
DELETE FROM projects WHERE id = 5201;
SELECT is((SELECT count(*)::INT FROM project_milestones WHERE project_id = 5201), 0,
          'deleting the project removes its milestones');

SELECT * FROM finish();
ROLLBACK;
