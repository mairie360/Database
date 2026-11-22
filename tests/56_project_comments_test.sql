BEGIN;
SELECT plan(14);

-- Comments of a project (releases/v4.0.0/06, MAIR-1089): written by Project_API, 1 to 2000
-- characters, newest first per project; like task_comments they are exported with their author's
-- data and kept, pointing to the anonymized account, when the author is erased.

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
VALUES (5500, 'Clea', 'Commenter', 'clea.commenter@project-comments.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
       (5501, 'Adam', 'Admin', 'adam.admin@project-comments.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
SET CONSTRAINTS ALL IMMEDIATE;
INSERT INTO user_roles (user_id, role_id) SELECT 5501, id FROM roles WHERE name = 'Admin';
INSERT INTO projects (id, title, owner_id) VALUES (5500, 'Market hall', 5501), (5501, 'Playground', 5501);

--- 1. STRUCTURE (5 tests)
SELECT has_table('project_comments');
SELECT col_is_pk('project_comments', 'id');
SELECT col_type_is('project_comments', 'created_at', 'timestamp with time zone', 'a comment keeps its time zone');
SELECT has_index('project_comments', 'idx_project_comments_project_created',
                 'comments of a project, newest first');
SELECT col_is_fk('project_comments', 'author_id', 'the author is a user');

--- 2. PRIVILEGES OF project_api (2 tests)
SELECT is(
    pg_temp.run_as('project_api', $$INSERT INTO project_comments (id, project_id, author_id, message)
                                    VALUES (5500, 5500, 5500, 'Delivery moved to Monday'),
                                           (5501, 5501, 5500, 'Fence ordered')$$),
    'ok', 'project_api writes a comment'
);
SELECT is(
    pg_temp.run_as('project_api', $$DELETE FROM project_comments WHERE id = 5501$$),
    'ok', 'project_api deletes a comment'
);

--- 3. CONSTRAINTS (3 tests)
SELECT throws_ok(
    $$INSERT INTO project_comments (project_id, author_id, message) VALUES (5500, 5500, '')$$,
    '23514', NULL, 'an empty comment is refused'
);
SELECT throws_ok(
    $$INSERT INTO project_comments (project_id, author_id, message) VALUES (5500, 5500, repeat('x', 2001))$$,
    '23514', NULL, 'a comment longer than 2000 characters is refused'
);
SELECT lives_ok(
    $$INSERT INTO project_comments (project_id, author_id, message) VALUES (5501, 5500, repeat('x', 2000))$$,
    'a comment of 2000 characters is accepted'
);

--- 4. EXPORT, ERASURE AND PROJECT DELETION (4 tests)
SELECT is(
    jsonb_array_length(export_user_data(5500) -> 'data' -> 'project_comments.author_id'),
    2, 'the comments of the user are exported'
);
SELECT lives_ok($$SELECT anonymize_user(5500)$$, 'the author is erased');
SELECT results_eq(
    $$SELECT author_id, message FROM project_comments WHERE id = 5500$$,
    $$VALUES (5500, 'Delivery moved to Monday'::TEXT)$$,
    'the comment stays, pointing to the anonymized account'
);
DELETE FROM projects WHERE id = 5501;
SELECT is((SELECT count(*)::INT FROM project_comments WHERE project_id = 5501), 0,
          'deleting the project removes its comments');

SELECT * FROM finish();
ROLLBACK;
