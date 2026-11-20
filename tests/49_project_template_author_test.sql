BEGIN;
SELECT plan(10);

-- Author of a project template: releases/v3.11.0/01. Project_API writes it on creation and reads
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
SELECT col_is_fk('project_templates', 'created_by', 'the author is a user');
SELECT is(
    (SELECT confdeltype::TEXT FROM pg_constraint
      WHERE conrelid = 'project_templates'::regclass AND contype = 'f'
        AND conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'project_templates'::regclass AND attname = 'created_by')]),
    'n', 'deleting the author clears the reference instead of deleting the template'
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
    pg_temp.run_as('project_api', $$INSERT INTO project_templates (name, created_by) VALUES ('Fantôme', 999999)$$),
    '23503', 'an author that is not a user is refused'
);

--- 4. DELETION OF THE AUTHOR (1 test)
DELETE FROM users WHERE id = 4900;
SELECT is(
    (SELECT created_by FROM project_templates WHERE name = 'Voirie 4900'), NULL,
    'the template stays, without author, when its author row is deleted'
);

SELECT * FROM finish();
ROLLBACK;
