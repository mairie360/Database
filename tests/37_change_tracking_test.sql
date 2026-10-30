BEGIN;
SELECT plan(16);

-- MAIR-524 (releases/v3.1.0): messages and conversations changed since a cursor
-- (messages.updated_at / edited_at / deleted_at, conversations.last_activity_at, kept by
-- repeatable/messages/fn_track_message_change.sql) and the cross-project task list
-- (idx_tasks_assignee_due, idx_tasks_active_due).

CREATE FUNCTION pg_temp.plan_of(p_sql TEXT) RETURNS TEXT AS $$
DECLARE
    v_line TEXT;
    v_plan TEXT := '';
BEGIN
    FOR v_line IN EXECUTE 'EXPLAIN (COSTS OFF) ' || p_sql LOOP
        v_plan := v_plan || v_line || E'\n';
    END LOOP;
    RETURN v_plan;
END;
$$ LANGUAGE plpgsql;

INSERT INTO users (id, first_name, last_name, email, password) VALUES
    (95240, 'Since', 'Sender', 'since.sender@example.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (95241, 'Since', 'Reader', 'since.reader@example.com', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
INSERT INTO conversations (id, title, kind, direct_user_low, direct_user_high, last_activity_at)
VALUES (95240, 'Since', 'direct', 95240, 95241, TIMESTAMPTZ '2026-01-01 08:00:00+00');
INSERT INTO conversation_members (conversation_id, user_id) VALUES (95240, 95240), (95240, 95241);

INSERT INTO messages (conversation_id, owner_id, content) VALUES (95240, 95240, 'first');
INSERT INTO messages (conversation_id, owner_id, content) VALUES (95240, 95240, 'second');
CREATE TEMP TABLE m AS
    SELECT id, content, updated_at FROM messages WHERE conversation_id = 95240 ORDER BY id;

SELECT ok(
    (SELECT max(updated_at) FROM m WHERE content = 'first') < (SELECT max(updated_at) FROM m WHERE content = 'second'),
    'A message sent later has a later updated_at, even in one transaction (clock time)'
);
SELECT is(
    (SELECT last_activity_at FROM conversations WHERE id = 95240),
    (SELECT max(updated_at) FROM m),
    'Sending a message moves the conversation activity to the message time'
);
SELECT is(
    (SELECT edited_at FROM messages WHERE content = 'first' AND conversation_id = 95240), NULL,
    'A message never edited has no edited_at'
);

UPDATE messages SET content = 'first, edited' WHERE conversation_id = 95240 AND content = 'first';
SELECT isnt(
    (SELECT edited_at FROM messages WHERE content = 'first, edited'), NULL,
    'Editing the content sets edited_at'
);
SELECT ok(
    (SELECT updated_at FROM messages WHERE content = 'first, edited') > (SELECT max(updated_at) FROM m),
    'An edit moves updated_at after every earlier change of the conversation'
);
SELECT is(
    (SELECT last_activity_at FROM conversations WHERE id = 95240),
    (SELECT updated_at FROM messages WHERE content = 'first, edited'),
    'An edit moves the conversation activity'
);

-- The read since a cursor of Message_API returns exactly the changes after it.
SELECT is(
    (SELECT array_agg(content ORDER BY updated_at, id) FROM messages
     WHERE conversation_id = 95240
       AND (updated_at, id) > (SELECT updated_at, id FROM m ORDER BY updated_at DESC, id DESC LIMIT 1)),
    ARRAY['first, edited'],
    'Only the edited message changed since the cursor'
);

-- Deletion = tombstone.
UPDATE messages SET deleted_at = CURRENT_TIMESTAMP
WHERE conversation_id = 95240 AND content = 'second';
SELECT is(
    (SELECT content FROM messages WHERE id = (SELECT id FROM m WHERE content = 'second')), '',
    'A deleted message keeps no content'
);
SELECT isnt(
    (SELECT deleted_at FROM messages WHERE id = (SELECT id FROM m WHERE content = 'second')), NULL,
    'A deleted message stays as a tombstone'
);
UPDATE messages SET content = 'resurrected' WHERE id = (SELECT id FROM m WHERE content = 'second');
SELECT is(
    (SELECT content FROM messages WHERE id = (SELECT id FROM m WHERE content = 'second')), '',
    'A tombstone cannot get content back'
);

-- The unread count of the reader ignores tombstones.
SELECT is(
    fn_acknowledge_read(95241, 95240, (SELECT min(id) FROM m)), 0,
    'A deleted message is not counted as unread'
);

-- Indexes and plans (sequential scans disabled: the plan must not depend on the data size).
SELECT has_index(
    'messages', 'idx_messages_conversation_updated', ARRAY['conversation_id', 'updated_at', 'id'],
    'Index of the changes of a conversation in cursor order'
);
SELECT has_index(
    'tasks', 'idx_tasks_assignee_due', ARRAY['assigned_to', 'due_date', 'id'],
    'Partial index of the active tasks of an assignee by due date'
);

-- A realistic shape: many active tasks of other assignees, a few of the caller.
INSERT INTO projects (id, title, owner_id) VALUES (95240, 'Since project', 95240);
INSERT INTO tasks (project_id, title, status, due_date, assigned_to)
SELECT 95240, 'Other ' || g, 'todo', TIMESTAMP '2026-01-01' + g * INTERVAL '1 hour', 95241
FROM generate_series(1, 2000) g;
INSERT INTO tasks (project_id, title, status, due_date, assigned_to)
SELECT 95240, 'Mine ' || g, CASE WHEN g <= 300 THEN 'completed' ELSE 'todo' END::task_status,
       TIMESTAMP '2026-01-01' + g * INTERVAL '1 hour', 95240
FROM generate_series(1, 400) g;
ANALYZE tasks;
ANALYZE messages;
SET LOCAL enable_seqscan = off;
SELECT alike(
    pg_temp.plan_of($$
        SELECT id FROM messages
        WHERE conversation_id = 95240 AND (updated_at, id) > (now() - interval '1 day', 0::BIGINT)
        ORDER BY updated_at, id LIMIT 100
    $$),
    '%idx_messages_conversation_updated%',
    'The changes since a cursor are read through idx_messages_conversation_updated'
);
SELECT alike(
    pg_temp.plan_of($$
        SELECT id FROM tasks
        WHERE assigned_to = 95240 AND archived_at IS NULL AND due_date < (now() AT TIME ZONE 'UTC')
        ORDER BY due_date NULLS LAST, id LIMIT 50
    $$),
    '%idx_tasks_assignee_due%',
    'The pending tasks of an assignee are read through idx_tasks_assignee_due'
);
SELECT alike(
    pg_temp.plan_of($$
        SELECT id FROM tasks WHERE archived_at IS NULL ORDER BY due_date, id LIMIT 50
    $$),
    '%idx_tasks_active_due%',
    'The active tasks by due date are read through idx_tasks_active_due'
);

SELECT * FROM finish();
ROLLBACK;
