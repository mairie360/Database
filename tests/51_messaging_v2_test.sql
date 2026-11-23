BEGIN;
SELECT plan(36);

-- Messaging V2 (MAIR-1155, releases/v4.0.0/02-04): reactions, system notes of the membership
-- changes, mentions of everyone and of groups.

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
VALUES
    (5100, 'Ada', 'Author', 'ada.author@messaging-v2.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (5101, 'Ben', 'Reader', 'ben.reader@messaging-v2.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (5102, 'Cleo', 'Third', 'cleo.third@messaging-v2.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');

INSERT INTO groups (id, name, owner_id) VALUES (5100, 'Voirie 5100', 5100), (5101, 'Culture 5101', 5100);
INSERT INTO group_members (group_id, user_id) VALUES (5100, 5100), (5100, 5101), (5100, 5102)
ON CONFLICT DO NOTHING;

-- 5100: group conversation of group 5100; 5101: direct conversation of 5100 and 5101.
INSERT INTO conversations (id, title, group_id, kind, direct_user_low, direct_user_high, created_by) VALUES
    (5100, 'Group', 5100, 'group', NULL, NULL, 5100),
    (5101, 'Direct', NULL, 'direct', 5100, 5101, 5100);
INSERT INTO conversation_members (conversation_id, user_id) VALUES
    (5100, 5100), (5100, 5101), (5100, 5102), (5101, 5100), (5101, 5101);

INSERT INTO messages (id, conversation_id, owner_id, content) VALUES
    (5100001, 5100, 5100, 'Hello team'),
    (5100002, 5101, 5100, 'Hello Ben');

---
--- 1. STRUCTURE (11 tests)
---
SELECT has_table('message_reactions');
SELECT col_is_pk('message_reactions', ARRAY['message_id', 'user_id', 'emoji'], 'one reaction per message, agent and emoji');
SELECT has_index('message_reactions', 'idx_message_reactions_user_id', 'the reactions of an agent are indexed');
SELECT has_table('message_group_mentions');
SELECT col_is_pk('message_group_mentions', ARRAY['message_id', 'group_id'], 'one mention per message and group');
SELECT has_index('message_group_mentions', 'idx_message_group_mentions_group_id', 'the mentions of a group are indexed');
SELECT col_default_is('messages', 'kind', 'user', 'a message is written by an agent by default');
SELECT col_not_null('messages', 'kind', 'messages.kind is mandatory');
SELECT col_is_null('messages', 'system_event', 'messages.system_event is set for system notes only');
SELECT col_default_is('messages', 'mentions_everyone', 'false', 'a message mentions nobody by default');
SELECT is(
    (SELECT kind || '/' || mentions_everyone::TEXT || '/' || coalesce(system_event::TEXT, 'null')
     FROM messages WHERE id = 5100001),
    'user/false/null',
    'a message inserted without the new columns is a user message without mention'
);

---
--- 2. REACTIONS (8 tests)
---
SELECT lives_ok(
    $$INSERT INTO message_reactions (message_id, user_id, emoji) VALUES
        (5100001, 5101, '👍'), (5100001, 5102, '👍'), (5100001, 5101, '👍🏽'), (5100001, 5102, '👨‍👩‍👧')$$,
    'emojis, skin tones and ZWJ sequences are accepted'
);
SELECT lives_ok(
    $$INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (5100001, 5101, '👍')
      ON CONFLICT DO NOTHING$$,
    'adding the same reaction again is idempotent'
);
SELECT is(
    (SELECT count(*)::INT FROM message_reactions WHERE message_id = 5100001 AND emoji = '👍'),
    2,
    'the repeated reaction left one row per agent'
);
SELECT throws_ok(
    $$INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (5100001, 5101, '👍')$$,
    '23505', NULL,
    'the same reaction twice without ON CONFLICT is a unique violation'
);
SELECT throws_ok(
    $$INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (5100001, 5101, '')$$,
    '23514', NULL,
    'an empty emoji is refused'
);
SELECT throws_ok(
    $$INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (5100001, 5101, 'a b')$$,
    '23514', NULL,
    'an emoji with whitespace is refused'
);
SELECT throws_ok(
    $$INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (5100001, 5101, E'\x01')$$,
    '23514', NULL,
    'an emoji with a control character is refused'
);
SELECT throws_ok(
    $$INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (5100001, 5101, repeat('x', 33))$$,
    '22001', NULL,
    'an emoji longer than 32 characters is refused'
);

---
--- 3. SYSTEM NOTES (9 tests)
---
SELECT lives_ok(
    $$INSERT INTO messages (id, conversation_id, owner_id, content, kind, system_event) VALUES
        (5100003, 5100, 5100, '', 'system', '{"action": "members_added", "actor_id": 5100, "user_ids": [5102]}')$$,
    'a system note is written with the actor as owner and an empty content'
);
SELECT throws_ok(
    $$INSERT INTO messages (conversation_id, owner_id, content, kind) VALUES (5100, 5100, '', 'system')$$,
    '23514', NULL,
    'a system note without its event is refused'
);
SELECT throws_ok(
    $$INSERT INTO messages (conversation_id, owner_id, content, system_event)
      VALUES (5100, 5100, 'Hi', '{"action": "member_left", "actor_id": 5100, "user_ids": [5100]}')$$,
    '23514', NULL,
    'a user message carrying an event is refused'
);
SELECT throws_ok(
    $$INSERT INTO messages (conversation_id, owner_id, content, kind) VALUES (5100, 5100, 'Hi', 'bot')$$,
    '23514', NULL,
    'an unknown kind is refused'
);
SELECT throws_ok(
    $$INSERT INTO messages (conversation_id, owner_id, content, kind, system_event)
      VALUES (5100, 5100, '', 'system', '{"action": "renamed", "actor_id": 5100, "user_ids": []}')$$,
    '23514', NULL,
    'an unknown action is refused'
);
SELECT throws_ok(
    $$INSERT INTO messages (conversation_id, owner_id, content, kind, system_event)
      VALUES (5100, 5100, '', 'system', '{"action": "member_removed", "actor_id": "5100", "user_ids": 5101}')$$,
    '23514', NULL,
    'an event without a numeric actor and a list of users is refused'
);

-- The note counts for nobody: the counters only hold the user message.
SELECT is(
    (SELECT count(*)::INT FROM unread_counters WHERE conversation_id = 5100 AND unread_count <> 1),
    0,
    'the system note did not increment the unread counters'
);

-- The acknowledgement recount skips the note too.
INSERT INTO messages (id, conversation_id, owner_id, content, kind, system_event) VALUES
    (5100004, 5100, 5100, '', 'system', '{"action": "member_removed", "actor_id": 5100, "user_ids": [5102]}');
SELECT is(
    fn_acknowledge_read(5101, 5100, 5100001),
    0,
    'the system notes after the cursor are not unread'
);

-- Deleting a note keeps the change tracking working (tombstone, updated_at moves).
UPDATE messages SET deleted_at = now() WHERE id = 5100004;
SELECT ok(
    (SELECT deleted_at IS NOT NULL AND content = '' AND kind = 'system' FROM messages WHERE id = 5100004),
    'a system note becomes a tombstone like any message'
);

---
--- 4. MENTIONS (4 tests)
---
SELECT lives_ok(
    $$INSERT INTO messages (id, conversation_id, owner_id, content, mentions_everyone)
      VALUES (5100005, 5100, 5100, '@everyone @Voirie', TRUE);
      INSERT INTO message_group_mentions (message_id, group_id) VALUES (5100005, 5100), (5100005, 5101)$$,
    'a message mentions everyone and groups'
);
SELECT throws_ok(
    $$INSERT INTO message_group_mentions (message_id, group_id) VALUES (5100005, 5100)$$,
    '23505', NULL,
    'a group is mentioned once per message'
);
DELETE FROM groups WHERE id = 5101;
SELECT is(
    (SELECT array_agg(group_id ORDER BY group_id) FROM message_group_mentions WHERE message_id = 5100005),
    ARRAY[5100],
    'deleting a group removes its mentions'
);
SELECT throws_ok(
    $$INSERT INTO message_group_mentions (message_id, group_id) VALUES (5100005, 999999)$$,
    '23503', NULL,
    'an unknown group cannot be mentioned'
);

---
--- 5. CASCADE (2 tests)
---
INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (5100005, 5101, '🎉');
DELETE FROM messages WHERE id = 5100005;
SELECT ok(
    NOT EXISTS (SELECT 1 FROM message_reactions WHERE message_id = 5100005)
    AND NOT EXISTS (SELECT 1 FROM message_group_mentions WHERE message_id = 5100005),
    'deleting a message removes its reactions and group mentions'
);
DELETE FROM conversation_members WHERE user_id = 5102;
DELETE FROM group_members WHERE user_id = 5102;
DELETE FROM unread_counters WHERE user_id = 5102;
DELETE FROM users WHERE id = 5102;
SELECT ok(
    NOT EXISTS (SELECT 1 FROM message_reactions WHERE user_id = 5102),
    'deleting an account removes its reactions'
);

---
--- 6. MESSAGE_API (2 tests)
---
SELECT is(
    pg_temp.run_as('message_api',
        $$INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (5100002, 5101, '❤️')
            ON CONFLICT DO NOTHING;
          DELETE FROM message_reactions WHERE message_id = 5100002 AND user_id = 5101 AND emoji = '❤️';
          INSERT INTO messages (conversation_id, owner_id, content, kind, system_event)
            VALUES (5101, 5101, '', 'system', '{"action": "member_left", "actor_id": 5101, "user_ids": [5101]}');
          INSERT INTO message_group_mentions (message_id, group_id) VALUES (5100002, 5100);
          DELETE FROM message_group_mentions WHERE message_id = 5100002;
          SELECT g.id, g.name FROM groups g JOIN group_members gm ON gm.group_id = g.id WHERE gm.user_id = 5101$$),
    'ok',
    'message_api reacts, writes a system note, mentions a group and lists the groups of a member'
);
SELECT is(
    pg_temp.run_as('message_api', $$UPDATE message_reactions SET emoji = '👎'$$),
    '42501',
    'message_api cannot rewrite a reaction'
);

SELECT * FROM finish();
ROLLBACK;
