BEGIN;
SELECT plan(14);

-- MAIR-478: one direct conversation per pair of agents (releases/v1.9.0).
-- The backfill of existing conversations is checked by tests/upgrade.

INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (3100, 'Direct', 'One', 'direct.one@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (3101, 'Direct', 'Two', 'direct.two@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (3102, 'Direct', 'Three', 'direct.three@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');

INSERT INTO groups (id, name, owner_id) VALUES (3100, 'Direct test group', 3100);

---
--- STRUCTURE
---
SELECT has_column('conversations', 'direct_user_low', 'conversations.direct_user_low exists');
SELECT has_column('conversations', 'direct_user_high', 'conversations.direct_user_high exists');

---
--- PAIR
---
SELECT lives_ok(
    $$INSERT INTO conversations (id, title, kind, direct_user_low, direct_user_high)
      VALUES (3100, '', 'direct', 3100, 3101)$$,
    'A direct conversation carries its two participants'
);
SELECT throws_ok(
    $$INSERT INTO conversations (title, kind, direct_user_low, direct_user_high)
      VALUES ('', 'direct', 3100, 3101)$$,
    '23505',
    NULL,
    'A pair has a single direct conversation'
);
SELECT throws_ok(
    $$INSERT INTO conversations (title, kind) VALUES ('', 'direct')$$,
    '23514',
    NULL,
    'A direct conversation names its participants'
);
SELECT throws_ok(
    $$INSERT INTO conversations (title, kind, direct_user_low, direct_user_high)
      VALUES ('', 'direct', 3101, 3100)$$,
    '23514',
    NULL,
    'The lowest id comes first, so a pair has a single spelling'
);
SELECT throws_ok(
    $$INSERT INTO conversations (title, kind, direct_user_low, direct_user_high)
      VALUES ('', 'direct', 3102, 3102)$$,
    '23514',
    NULL,
    'A direct conversation is between two different agents'
);
SELECT throws_ok(
    $$INSERT INTO conversations (title, group_id, kind, direct_user_low, direct_user_high)
      VALUES ('', 3100, 'direct', 3100, 3102)$$,
    '23514',
    NULL,
    'A direct conversation has no group'
);
SELECT throws_ok(
    $$INSERT INTO conversations (title, kind, direct_user_low, direct_user_high)
      VALUES ('Team', 'group', 3100, 3102)$$,
    '23514',
    NULL,
    'A group conversation has no participant pair'
);
SELECT lives_ok(
    $$INSERT INTO conversations (title, kind) VALUES ('Team', 'group'), ('Team', 'group')$$,
    'Group conversations are not limited by the pair constraint'
);

---
--- RESOURCE
---
-- check_access() knows `conversations`: the global right of the Admin role,
-- nothing for an agent without ACL, an individual ACL on one conversation.
SELECT is(check_access(1, 'conversations', 'delete', 3100), 1, 'An administrator may delete any conversation');
SELECT is(check_access(3102, 'conversations', 'delete', 3100), 0, 'An agent without right may not delete a conversation');
INSERT INTO access_control (user_id, resource_id, resource_instance_id, permission_id)
SELECT 3102, res.id, 3100, p.id
FROM resources res JOIN permissions p ON p.resource_id = res.id
WHERE res.name = 'conversations' AND p.action = 'delete';
SELECT is(check_access(3102, 'conversations', 'delete', 3100), 1, 'An ACL grants the deletion of one conversation');

---
--- CASCADE
---
-- Users are archived, never deleted, by the platform; a hard delete takes the
-- direct conversation with it, like its membership rows.
DELETE FROM users WHERE id = 3101;
SELECT ok(
    NOT EXISTS (SELECT 1 FROM conversations WHERE id = 3100),
    'Deleting a participant account deletes the direct conversation'
);

SELECT * FROM finish();
ROLLBACK;
