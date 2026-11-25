BEGIN;
SELECT plan(10);

-- Author of a project template: releases/v4.0.0/v3_11_0__01, without foreign key since releases/v4.0.0/v3_11_1__01. Project_API writes it on creation and reads
-- it to decide who may modify or delete a template; the four seeded templates belong to the
-- system admin (users.id = 1).

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
VALUES (4900, 'Rita', 'Author', 'rita.author@template-author.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');

--- 1. STRUCTURE (4 tests)
SELECT has_column('project_templates', 'created_by', 'a template has an author');
-- A foreign key to users would make the TRUNCATE users CASCADE of the API test harness empty the
-- templates and their statuses.
SELECT col_isnt_fk('project_templates', 'created_by', 'the author is not a foreign key');
SELECT is(
    (SELECT count(*) FROM pg_constraint WHERE confrelid = 'users'::regclass AND conrelid = 'project_templates'::regclass)::INT,
    0, 'no constraint links project_templates to users'
);

SELECT has_index('project_templates', 'idx_project_templates_created_by', 'the author lookup is indexed');

--- 2. EXISTING TEMPLATES (2 tests)
SELECT is(
    (SELECT count(*) FROM project_templates WHERE name IN ('Simple', 'Avec validation', 'Marché public', 'Événement') AND created_by = 1)::INT,
    4, 'the four seeded templates belong to the system admin'
);
SELECT is_empty(
    $$SELECT id FROM project_templates WHERE created_by IS NULL$$,
    'no template is left without an author on a migrated database'
);

--- 3. PRIVILEGES OF project_api (3 tests)
SELECT is(
    pg_temp.run_as('project_api', $$INSERT INTO project_templates (name, created_by) VALUES ('Voirie 4900', 4900)$$),
    'ok', 'project_api writes the author of a template'
);
SELECT is(
    pg_temp.run_as('project_api', $$SELECT created_by FROM project_templates WHERE name = 'Voirie 4900'$$),
    'ok', 'project_api reads the author of a template'
);
SELECT is(
    pg_temp.run_as('project_api', $$UPDATE project_templates SET name = 'Voirie 4900 bis' WHERE name = 'Voirie 4900'$$),
    'ok', 'project_api modifies a template'
);

--- 4. TRUNCATE OF THE USERS (1 test)
-- What the API test harness runs first: the templates and their statuses must survive it.
SET CONSTRAINTS ALL IMMEDIATE;
TRUNCATE TABLE users RESTART IDENTITY CASCADE;
SELECT cmp_ok(
    (SELECT count(*) FROM project_template_statuses)::INT, '>', 0,
    'the templates and their statuses survive TRUNCATE users CASCADE'
);

SELECT * FROM finish();
ROLLBACK;
