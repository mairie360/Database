BEGIN;
SELECT plan(23);

-- MAIR-269: explicit read acknowledgement (fn_acknowledge_read,
-- conversation_read_cursors) and per-conversation message id assignment
-- (fn_before_message_insert).

---
--- SEED
---

INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (2600, 'Sender', 'One', 'ack.sender@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (2601, 'Reader', 'Two', 'ack.reader@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (2602, 'Third', 'Three', 'ack.third@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (2603, 'Outsider', 'Four', 'ack.outsider@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');

INSERT INTO groups (id, name, owner_id) VALUES (2600, 'Ack group', 2600);
INSERT INTO group_members (group_id, user_id) VALUES (2600, 2600), (2600, 2601), (2600, 2602)
ON CONFLICT DO NOTHING;

-- 2600: direct chat between 2600 and 2601, 2601: group chat, 2602: direct chat
-- with an excluded member (2602), 2603: a chat without group of the same two
-- agents (foreign cursor).
INSERT INTO conversations (id, title, group_id, kind, direct_user_low, direct_user_high) VALUES
    (2600, 'Direct', NULL, 'direct', 2600, 2601),
    (2601, 'Group', 2600, 'group', NULL, NULL),
    (2602, 'Excluded', NULL, 'direct', 2600, 2602),
    (2603, 'Other', NULL, 'group', NULL, NULL);
INSERT INTO conversation_members (conversation_id, user_id, is_excluded) VALUES
    (2600, 2600, FALSE), (2600, 2601, FALSE),
    (2602, 2600, FALSE), (2602, 2602, TRUE),
    (2603, 2600, FALSE), (2603, 2601, FALSE);

CREATE TEMP TABLE msg (name TEXT PRIMARY KEY, id BIGINT NOT NULL);

-- Sends a message (id drawn by the trigger) and remembers its id under p_name.
CREATE FUNCTION pg_temp.send(p_name TEXT, p_conversation INT, p_owner INT) RETURNS VOID AS $$
    WITH ins AS (
        INSERT INTO messages (conversation_id, owner_id, content)
        VALUES (p_conversation, p_owner, 'ack test ' || p_name)
        RETURNING id
    )
    INSERT INTO msg SELECT p_name, id FROM ins;
$$ LANGUAGE sql;

CREATE FUNCTION pg_temp.mid(p_name TEXT) RETURNS BIGINT AS $$
    SELECT id FROM msg WHERE name = p_name;
$$ LANGUAGE sql;

SELECT pg_temp.send('m1', 2600, 2600);
SELECT pg_temp.send('m2', 2600, 2600);
SELECT pg_temp.send('m3', 2600, 2600);

---
--- STRUCTURE
---
SELECT has_table('conversation_read_cursors');
SELECT has_function('fn_acknowledge_read', ARRAY['integer', 'integer', 'bigint']);

---
--- DIRECT CHAT
---

SELECT is(
    (SELECT unread_count FROM unread_counters WHERE conversation_id = 2600 AND user_id = 2601),
    3,
    'Three messages sent: the reader has three unread'
);

SELECT is(
    fn_acknowledge_read(2601, 2600, pg_temp.mid('m2')),
    1,
    'Acknowledging up to m2 leaves only m3 unread'
);

SELECT is(
    (SELECT unread_count FROM unread_counters WHERE conversation_id = 2600 AND user_id = 2601),
    1,
    'The persisted counter matches the returned count'
);

SELECT is(
    fn_acknowledge_read(2601, 2600, pg_temp.mid('m1')),
    1,
    'A stale acknowledgement (m1) does not resurrect read messages'
);

SELECT is(
    (SELECT last_read_message_id FROM conversation_read_cursors
     WHERE conversation_id = 2600 AND user_id = 2601),
    pg_temp.mid('m2'),
    'The cursor never moves backwards'
);

SELECT is(
    fn_acknowledge_read(2601, 2600, pg_temp.mid('m3')),
    0,
    'Acknowledging up to the last message leaves nothing unread'
);

SELECT ok(
    NOT EXISTS (SELECT 1 FROM unread_counters WHERE conversation_id = 2600 AND user_id = 2601),
    'A zero count leaves no unread_counters row'
);

SELECT is(
    fn_acknowledge_read(2601, 2600, pg_temp.mid('m3')),
    0,
    'Repeating an acknowledgement is idempotent'
);

-- A message sent after the cursor is counted, and a stale cursor cannot clear it.
SELECT pg_temp.send('m4', 2600, 2600);

SELECT is(
    (SELECT unread_count FROM unread_counters WHERE conversation_id = 2600 AND user_id = 2601),
    1,
    'A message sent after the acknowledgement is unread'
);

SELECT is(
    fn_acknowledge_read(2601, 2600, pg_temp.mid('m3')),
    1,
    'Acknowledging the previous cursor again does not clear the new message'
);

SELECT is(
    fn_acknowledge_read(2601, 2600, pg_temp.mid('m1')),
    1,
    'Nor does an older cursor'
);

SELECT is(
    fn_acknowledge_read(2600, 2600, pg_temp.mid('m4')),
    0,
    'The sender never has unread messages from their own posts'
);

---
--- REJECTED CURSORS AND NON-RECIPIENTS
---

SELECT pg_temp.send('other', 2603, 2600);

SELECT is(
    fn_acknowledge_read(2601, 2600, pg_temp.mid('other')),
    NULL,
    'A message id from another conversation is refused (NULL)'
);

SELECT is(
    fn_acknowledge_read(2601, 2600, 999999999),
    NULL,
    'An unknown message id is refused (NULL)'
);

SELECT pg_temp.send('excl', 2602, 2600);

SELECT is(
    fn_acknowledge_read(2602, 2602, pg_temp.mid('excl')),
    0,
    'An excluded member has nothing unread'
);

SELECT ok(
    NOT EXISTS (SELECT 1 FROM unread_counters WHERE conversation_id = 2602 AND user_id = 2602),
    'An excluded member never gets a counter row'
);

---
--- GROUP CHAT
---

SELECT pg_temp.send('g1', 2601, 2600);
SELECT pg_temp.send('g2', 2601, 2600);

SELECT is(
    fn_acknowledge_read(2601, 2601, pg_temp.mid('g2')),
    0,
    'A group member acknowledges the group conversation'
);

SELECT is(
    (SELECT unread_count FROM unread_counters WHERE conversation_id = 2601 AND user_id = 2602),
    2,
    'Cursors are per agent: another member keeps their unread messages'
);

SELECT is(
    fn_acknowledge_read(2603, 2601, pg_temp.mid('g2')),
    0,
    'An agent outside the group has nothing unread'
);

---
--- MESSAGE IDS
---

INSERT INTO messages (id, conversation_id, owner_id, content)
VALUES (990001, 2600, 2600, 'explicit id');

SELECT is(
    (SELECT id FROM messages WHERE content = 'explicit id'),
    990001::BIGINT,
    'An explicit message id is kept'
);

SELECT ok(
    pg_temp.mid('m4') > pg_temp.mid('m3') AND pg_temp.mid('m3') > pg_temp.mid('m2'),
    'Ids drawn by the trigger increase in send order'
);

SELECT * FROM finish();
ROLLBACK;
