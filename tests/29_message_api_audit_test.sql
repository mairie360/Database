BEGIN;
SELECT plan(16);

-- MAIR-394: conversation creator, message replies and moderation log
-- (releases/v1.8.0).

-- Runs `p_sql` as `p_role` and returns 'ok' or the SQLSTATE it raised.
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

---
--- SEED
---

INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (2700, 'Creator', 'One', 'audit.creator@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (2701, 'Member', 'Two', 'audit.member@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');

INSERT INTO conversations (id, title, kind, created_by) VALUES
    (2700, 'Audit chat', 'direct', 2700),
    (2701, 'Other chat', 'direct', 2700);
INSERT INTO conversation_members (conversation_id, user_id) VALUES
    (2700, 2700), (2700, 2701), (2701, 2700);

INSERT INTO messages (id, conversation_id, owner_id, content) VALUES
    (27000, 2700, 2700, 'Quoted message'),
    (27001, 2701, 2700, 'Message of another chat');

---
--- STRUCTURE
---
SELECT has_column('conversations', 'created_by', 'conversations.created_by exists');
SELECT col_is_null('conversations', 'created_by', 'created_by is nullable');
SELECT has_column('messages', 'reply_to_id', 'messages.reply_to_id exists');
SELECT has_table('messaging_moderation_log');

---
--- REPLIES
---
SELECT lives_ok(
    $$INSERT INTO messages (id, conversation_id, owner_id, content, reply_to_id)
      VALUES (27002, 2700, 2701, 'Reply', 27000)$$,
    'A message may reply to a message of the same conversation'
);
SELECT throws_ok(
    $$INSERT INTO messages (conversation_id, owner_id, content, reply_to_id)
      VALUES (2700, 2701, 'Cross reply', 27001)$$,
    '23503',
    NULL,
    'A message cannot reply to a message of another conversation'
);
SELECT throws_ok(
    $$INSERT INTO messages (conversation_id, owner_id, content, reply_to_id)
      VALUES (2700, 2701, 'Dangling reply', 99999999)$$,
    '23503',
    NULL,
    'A message cannot reply to an unknown message'
);

DELETE FROM messages WHERE id = 27000;
SELECT is(
    (SELECT reply_to_id FROM messages WHERE id = 27002),
    NULL,
    'Deleting the quoted message only clears reply_to_id'
);
SELECT is(
    (SELECT conversation_id FROM messages WHERE id = 27002),
    2700,
    'The reply keeps its conversation'
);

---
--- CREATOR
---
DELETE FROM users WHERE id = 2700;
SELECT is(
    (SELECT created_by FROM conversations WHERE id = 2700),
    NULL,
    'Deleting the creator account clears created_by'
);
SELECT ok(
    EXISTS (SELECT 1 FROM conversations WHERE id = 2700),
    'The conversation survives its creator'
);

---
--- MODERATION LOG
---
SELECT is(
    pg_temp.run_as('message_api',
        $$INSERT INTO messaging_moderation_log
              (action, conversation_id, message_id, target_user_id, content, performed_by)
          VALUES ('DELETE_MESSAGE', 2700, 27002, 2701, 'Reply', 1)$$),
    'ok',
    'message_api can append to the moderation log'
);
SELECT is(
    pg_temp.run_as('message_api', $$UPDATE messaging_moderation_log SET content = 'x'$$),
    '42501',
    'message_api cannot rewrite the moderation log'
);
SELECT is(
    pg_temp.run_as('message_api', $$DELETE FROM messaging_moderation_log$$),
    '42501',
    'message_api cannot erase the moderation log'
);
SELECT throws_ok(
    $$INSERT INTO messaging_moderation_log (action, conversation_id, performed_by)
      VALUES ('DELETE_MESSAGE', 2700, 1)$$,
    '23514',
    NULL,
    'A message deletion entry names the message'
);
SELECT lives_ok(
    $$INSERT INTO messaging_moderation_log (action, conversation_id, content, performed_by)
      VALUES ('DELETE_CONVERSATION', 2700, 'Audit chat', 1)$$,
    'A conversation deletion entry has no message'
);

SELECT * FROM finish();
ROLLBACK;
