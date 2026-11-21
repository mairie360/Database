BEGIN;
SELECT plan(8);

-- Role of a member in a project (releases/v4.0.0/05, MAIR-1088): manager, contributor or reader,
-- `contributor` when the writer does not say (the members added before this release and the
-- Project_API release in prod, which does not send the column).

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
VALUES (5400, 'Rosa', 'Owner', 'rosa.owner@member-roles.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
       (5401, 'Remi', 'Member', 'remi.member@member-roles.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
       (5402, 'Rui', 'Reader', 'rui.reader@member-roles.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
INSERT INTO projects (id, title, owner_id) VALUES (5400, 'Sports hall', 5400);

--- 1. STRUCTURE (4 tests)
SELECT has_enum('project_member_role');
SELECT enum_has_labels('project_member_role', ARRAY['manager', 'contributor', 'reader'],
                       'the three roles of a project member, in order');
SELECT col_type_is('project_members', 'role', 'project_member_role', 'a member holds a project role');
SELECT col_not_null('project_members', 'role', 'every member has a role');

--- 2. VALUES (4 tests)
SELECT is(
    pg_temp.run_as('project_api', $$INSERT INTO project_members (project_id, user_id) VALUES (5400, 5401)$$),
    'ok', 'project_api adds a member without role (release in prod)'
);
SELECT is((SELECT role::TEXT FROM project_members WHERE project_id = 5400 AND user_id = 5401), 'contributor',
          'a member added without role is a contributor');
SELECT is(
    pg_temp.run_as('project_api', $$INSERT INTO project_members (project_id, user_id, role) VALUES (5400, 5402, 'reader');
                                    UPDATE project_members SET role = 'manager' WHERE project_id = 5400 AND user_id = 5401$$),
    'ok', 'project_api sets and changes the role of a member'
);
SELECT throws_ok(
    $$UPDATE project_members SET role = 'owner' WHERE project_id = 5400 AND user_id = 5401$$,
    '22P02', NULL, 'an unknown role is refused'
);

SELECT * FROM finish();
ROLLBACK;
