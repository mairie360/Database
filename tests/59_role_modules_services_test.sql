BEGIN;
SELECT plan(16);

-- Modules of a role (MAIR-916), services of the mairie and colour of a group (MAIR-923),
-- releases/v4.0.0/13-15.

-- Tests 1-4: the existing roles open every module, Administration for Admin only.
SELECT is(
    (SELECT array_agg(module ORDER BY module) FROM role_modules rm JOIN roles r ON r.id = rm.role_id WHERE r.name = 'Admin'),
    ARRAY['admin', 'calendar', 'dashboard', 'messages', 'projects', 'settings', 'training'],
    'the Admin role opens every module'
);
SELECT is(
    (SELECT count(*)::INT FROM role_modules rm JOIN roles r ON r.id = rm.role_id WHERE r.name <> 'Admin' AND rm.module = 'admin'),
    0,
    'no other role opens Administration'
);
SELECT throws_ok(
    $$INSERT INTO role_modules (role_id, module) SELECT id, 'files' FROM roles WHERE name = 'Admin'$$,
    '23514', NULL,
    'an unknown module is refused'
);
SELECT throws_ok(
    $$DELETE FROM role_modules WHERE module = 'admin' AND role_id = (SELECT id FROM roles WHERE name = 'Admin')$$,
    '23514', 'The Admin role always opens the Administration module',
    'the Admin role keeps Administration'
);

-- Tests 5-7: the other modules stay free, a deleted role takes its modules with it.
INSERT INTO roles (id, name, description) VALUES (9970, 'Stagiaire 59', 'Test role');
INSERT INTO role_modules (role_id, module) VALUES (9970, 'dashboard'), (9970, 'projects');
SELECT lives_ok(
    $$DELETE FROM role_modules WHERE role_id = 9970 AND module = 'projects'$$,
    'a module of another role can be removed'
);
SELECT lives_ok(
    $$DELETE FROM role_modules WHERE module = 'calendar' AND role_id = (SELECT id FROM roles WHERE name = 'Admin')$$,
    'the Admin role may lose another module'
);
DELETE FROM roles WHERE id = 9970;
SELECT is((SELECT count(*)::INT FROM role_modules WHERE role_id = 9970), 0, 'deleting a role deletes its modules');

-- Tests 8-12: services, unique whatever the case, and the service of an agent.
INSERT INTO services (id, name) VALUES (9971, 'Voirie');
SELECT throws_ok($$INSERT INTO services (name) VALUES ('voirie')$$, '23505', NULL, 'a service name is unique whatever its case');
SELECT throws_ok($$INSERT INTO services (name) VALUES ('   ')$$, '23514', NULL, 'a blank service name is refused');
INSERT INTO users (id, first_name, last_name, email, password, service_id)
VALUES (9972, 'Sara', 'Service', 'sara.service@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 9971);
SELECT is((SELECT service_id FROM users WHERE id = 9972), 9971, 'an agent belongs to a service');
DELETE FROM services WHERE id = 9971;
SELECT is((SELECT service_id FROM users WHERE id = 9972), NULL::INT, 'deleting a service leaves its agents without one');
SELECT has_index('public', 'users', 'idx_users_service_id', 'users.service_id is indexed');

-- Tests 13-15: the colour of a group is a name of the palette or NULL.
SELECT col_is_null('public', 'groups', 'color', 'groups.color is optional');
SELECT throws_ok(
    $$INSERT INTO groups (owner_id, name, color) VALUES (9972, 'Groupe 59', '#ff0000')$$,
    '23514', NULL,
    'a colour outside the palette is refused'
);
SELECT lives_ok(
    $$INSERT INTO groups (owner_id, name, color) VALUES (9972, 'Groupe 59', 'teal')$$,
    'a colour of the palette is accepted'
);

-- Test 16: core_api reads the groups of a project, without writing them.
SELECT ok(
    has_column_privilege('core_api', 'project_groups', 'group_id', 'SELECT')
    AND NOT has_table_privilege('core_api', 'project_groups', 'INSERT'),
    'core_api counts the projects of a group without writing project_groups'
);

SELECT * FROM finish();
ROLLBACK;
