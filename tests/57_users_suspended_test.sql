BEGIN;
SELECT plan(7);

-- Suspended accounts (MAIR-904, releases/v4.0.0/10): `users.status` accepts 'suspended', and a
-- suspended account is denied like an archived one, while keeping its roles.

INSERT INTO users (id, first_name, last_name, email, password)
VALUES (9960, 'Sam', 'Suspended', 'sam.suspended@test.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
INSERT INTO user_roles (user_id, role_id)
SELECT 9960, id FROM roles WHERE name = 'Admin';
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
INSERT INTO resources (name) VALUES ('groups') ON CONFLICT DO NOTHING;
INSERT INTO permissions (resource_id, action)
SELECT id, 'read_all' FROM resources WHERE name = 'groups' ON CONFLICT DO NOTHING;
INSERT INTO rights (role_id, permission_id)
SELECT (SELECT id FROM roles WHERE name = 'Admin'), p.id
FROM permissions p JOIN resources r ON r.id = p.resource_id
WHERE r.name = 'groups' AND p.action = 'read_all'
ON CONFLICT DO NOTHING;

-- Test 1: an active Admin is admin and reads every group.
SELECT ok(is_admin(9960), 'an active Admin is admin');
SELECT is(check_access(9960, 'groups', 'read', NULL), 1, 'an active Admin may read the groups');

-- Test 3: the status accepts 'suspended', any other unknown value is still refused.
SELECT lives_ok(
    $$UPDATE users SET status = 'suspended' WHERE id = 9960$$,
    'users.status accepts suspended'
);
SELECT throws_ok(
    $$UPDATE users SET status = 'frozen' WHERE id = 9960$$,
    '23514',
    NULL,
    'users.status still refuses an unknown value'
);

-- Test 5: suspended, the account keeps its role but is neither admin nor allowed anything.
SELECT ok(NOT is_admin(9960), 'a suspended Admin is not admin');
SELECT is(check_access(9960, 'groups', 'read', NULL), 0, 'a suspended account is denied');
SELECT is(
    (SELECT count(*)::int FROM user_roles WHERE user_id = 9960),
    1,
    'a suspended account keeps its role'
);

SELECT * FROM finish();
ROLLBACK;
