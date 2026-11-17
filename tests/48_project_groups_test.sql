BEGIN;
SELECT plan(9);

-- Groups linked to a project: releases/v3.9.0/01. Project_API writes the link and reads the
-- group (id, name) to check it; the link goes when the project or the group is deleted.

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
VALUES (4800, 'Lina', 'Owner', 'lina.owner@project-groups.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
INSERT INTO groups (id, owner_id, name) VALUES (4800, 4800, 'Voirie 4800'), (4801, 4800, 'Espaces verts 4801');
INSERT INTO projects (id, title, owner_id) VALUES (4800, 'Market square', 4800), (4801, 'Park', 4800);

--- 1. STRUCTURE (3 tests)
SELECT has_table('project_groups');
SELECT col_is_pk('project_groups', ARRAY['project_id', 'group_id'], 'one link per project and group');
SELECT has_index('project_groups', 'idx_project_groups_group_id', 'lookup from the groups of a user');

--- 2. PRIVILEGES OF project_api (3 tests)
SELECT is(
    pg_temp.run_as('project_api', $$INSERT INTO project_groups (project_id, group_id) VALUES (4800, 4800)$$),
    'ok', 'project_api links a group to a project'
);
SELECT is(
    pg_temp.run_as('project_api', $$SELECT id, name FROM groups WHERE id = 4800$$),
    'ok', 'project_api reads the id and the name of a group'
);
SELECT is(
    pg_temp.run_as('project_api', $$SELECT description FROM groups WHERE id = 4800$$),
    '42501', 'project_api cannot read the rest of a group'
);

--- 3. LINK LIFECYCLE (3 tests)
SELECT throws_ok(
    $$INSERT INTO project_groups (project_id, group_id) VALUES (4800, 999999)$$,
    '23503', NULL, 'an unknown group is refused'
);
INSERT INTO project_groups (project_id, group_id) VALUES (4801, 4801);
DELETE FROM groups WHERE id = 4801;
SELECT is((SELECT count(*)::INT FROM project_groups WHERE project_id = 4801), 0, 'deleting the group removes the link');
DELETE FROM projects WHERE id = 4800;
SELECT is((SELECT count(*)::INT FROM project_groups WHERE group_id = 4800), 0, 'deleting the project removes the link');

SELECT * FROM finish();
ROLLBACK;
