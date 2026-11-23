BEGIN;
SELECT plan(12);

-- project_visible_to_user(user, project) (MAIR-1166, repeatable/project/fn_project_visible_to_user.sql):
-- the visibility rule of Project_API, which Message_API applies to the project and task links of a
-- message.

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

CREATE FUNCTION pg_temp.give_role(p_user INT, p_role TEXT) RETURNS VOID AS $$
    INSERT INTO user_roles (user_id, role_id) VALUES (p_user, (SELECT id FROM roles WHERE name = p_role))
    ON CONFLICT (user_id) DO UPDATE SET role_id = EXCLUDED.role_id;
$$ LANGUAGE sql;

INSERT INTO users (id, first_name, last_name, email, password)
SELECT n, 'Agent', 'N' || n, 'agent' || n || '@project-visible.test',
       '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'
FROM generate_series(6100, 6107) AS n;
-- 6100 owner, 6101 member, 6102 outsider, 6103 Maire, 6104 Responsable of the owner's team,
-- 6105 member of the linked group, 6106 member then archived, 6107 Responsable of another team.
SELECT pg_temp.give_role(n, 'User') FROM generate_series(6100, 6107) AS n;
SELECT pg_temp.give_role(6103, 'Maire');
SELECT pg_temp.give_role(6104, 'Responsable');
SELECT pg_temp.give_role(6107, 'Responsable');

INSERT INTO groups (id, owner_id, name) VALUES
    (6100, 6104, 'Team 6100'), (6101, 6105, 'Linked 6101'), (6102, 6107, 'Other 6102');
INSERT INTO group_members (group_id, user_id) VALUES
    (6100, 6104), (6100, 6100), (6101, 6105), (6102, 6107), (6102, 6102)
ON CONFLICT DO NOTHING;

INSERT INTO projects (id, title, owner_id) VALUES (6100, 'Roads 6100', 6100);
INSERT INTO project_members (project_id, user_id) VALUES (6100, 6101), (6100, 6106);
INSERT INTO project_groups (project_id, group_id) VALUES (6100, 6101);
UPDATE users SET is_archived = TRUE WHERE id = 6106;

--- 1. THE RULE OF PROJECT_API (9 tests)
SELECT ok(project_visible_to_user(6103, 6100), 'a Maire sees every project');
SELECT ok(project_visible_to_user(6100, 6100), 'the owner sees the project');
SELECT ok(project_visible_to_user(6101, 6100), 'a member sees the project');
SELECT ok(project_visible_to_user(6105, 6100), 'a member of a linked group sees the project');
SELECT ok(project_visible_to_user(6104, 6100), 'a Responsable sees the projects of their team');
SELECT ok(NOT project_visible_to_user(6107, 6100), 'a Responsable of another team does not');
SELECT ok(NOT project_visible_to_user(6102, 6100), 'an outsider does not');
SELECT ok(NOT project_visible_to_user(6106, 6100), 'an archived member does not');
SELECT ok(NOT project_visible_to_user(6103, 999999), 'an unknown project is visible to nobody');

--- 2. PRIVILEGES (3 tests)
SELECT is(
    pg_temp.run_as('message_api', $$SELECT project_visible_to_user(6101, 6100)$$),
    'ok', 'message_api runs it'
);
SELECT is(
    pg_temp.run_as('message_api', $$SELECT owner_id FROM projects$$),
    '42501', 'message_api still cannot read the projects'
);
SELECT ok(
    (SELECT prosecdef FROM pg_proc WHERE proname = 'project_visible_to_user'),
    'the function runs with its owner''s rights'
);

SELECT * FROM finish();
ROLLBACK;
