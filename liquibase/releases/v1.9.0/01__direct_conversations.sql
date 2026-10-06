-- MAIR-478: one direct conversation per pair of agents.
--
-- Message_API wrote kind = 'direct' for every conversation without a group, so
-- the column told nothing, and leaving a conversation deleted the membership
-- row: once a participant had left a direct conversation, nobody knew who the
-- contact was, and the BFF created a second one on the next message.
--
-- conversations.direct_user_low / direct_user_high: the two participants of a
-- direct conversation (lowest id first), NULL for any other kind. The unique
-- pair makes a duplicate direct conversation impossible, and keeps the contact
-- known whatever the membership rows say. Hiding a direct conversation is now
-- conversation_members.is_excluded = TRUE (Message_API), not a deleted row.
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS direct_user_low INT REFERENCES users(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS direct_user_high INT REFERENCES users(id) ON DELETE CASCADE;

---
-- Backfill
---
-- The participants of each candidate: its members, the id in the `Direct <id>`
-- title the BFF gives the conversations it creates, the creator and the
-- authors of its messages (a participant who left only remains there). Only
-- conversations without a group and with the BFF title or no title are
-- candidates, and a candidate is direct when exactly two agents come out.
CREATE TEMP TABLE mair478_direct ON COMMIT DROP AS
SELECT c.id AS conversation_id, p.users[1] AS user_low, p.users[2] AS user_high
FROM conversations c
CROSS JOIN LATERAL (
    SELECT array_agg(DISTINCT s.user_id ORDER BY s.user_id) AS users
    FROM (
        SELECT m.user_id FROM conversation_members m WHERE m.conversation_id = c.id
        UNION SELECT substring(c.title FROM '^Direct ([0-9]{1,9})$')::INT
        UNION SELECT c.created_by
        UNION SELECT msg.owner_id FROM messages msg WHERE msg.conversation_id = c.id
    ) s
    WHERE s.user_id IS NOT NULL AND EXISTS (SELECT 1 FROM users u WHERE u.id = s.user_id)
) p
WHERE c.group_id IS NULL
  AND (c.title ~ '^Direct [0-9]{1,9}$' OR COALESCE(c.title, '') = '')
  AND cardinality(p.users) = 2;

-- Duplicates of a pair (the bug) are merged into its oldest conversation.
CREATE TEMP TABLE mair478_merge ON COMMIT DROP AS
SELECT d.conversation_id AS duplicate_id, k.keeper_id
FROM mair478_direct d
JOIN (
    SELECT user_low, user_high, min(conversation_id) AS keeper_id
    FROM mair478_direct
    GROUP BY user_low, user_high
) k USING (user_low, user_high)
WHERE d.conversation_id <> k.keeper_id;

-- Messages keep their ids, so their order and the read cursors stay meaningful.
-- A reply and the message it quotes move in the same statement, which keeps
-- fk_messages_reply_to satisfied.
UPDATE messages msg
SET conversation_id = mg.keeper_id
FROM mair478_merge mg
WHERE msg.conversation_id = mg.duplicate_id;

-- A participant sees the merged conversation when they saw any of its copies.
INSERT INTO conversation_members (conversation_id, user_id, is_excluded, joined_at)
SELECT mg.keeper_id, m.user_id, bool_and(m.is_excluded), min(m.joined_at)
FROM mair478_merge mg
JOIN conversation_members m ON m.conversation_id = mg.duplicate_id
GROUP BY mg.keeper_id, m.user_id
ON CONFLICT (conversation_id, user_id) DO UPDATE
SET is_excluded = conversation_members.is_excluded AND EXCLUDED.is_excluded,
    joined_at = LEAST(conversation_members.joined_at, EXCLUDED.joined_at);

-- Unread messages add up; the earliest cursor is kept, fn_acknowledge_read
-- recounts on the next acknowledgement.
INSERT INTO unread_counters (conversation_id, user_id, unread_count)
SELECT mg.keeper_id, uc.user_id, sum(uc.unread_count)::INT
FROM mair478_merge mg
JOIN unread_counters uc ON uc.conversation_id = mg.duplicate_id
GROUP BY mg.keeper_id, uc.user_id
ON CONFLICT (user_id, conversation_id) DO UPDATE
SET unread_count = unread_counters.unread_count + EXCLUDED.unread_count;

INSERT INTO conversation_read_cursors (conversation_id, user_id, last_read_message_id)
SELECT mg.keeper_id, rc.user_id, min(rc.last_read_message_id)
FROM mair478_merge mg
JOIN conversation_read_cursors rc ON rc.conversation_id = mg.duplicate_id
GROUP BY mg.keeper_id, rc.user_id
ON CONFLICT (user_id, conversation_id) DO UPDATE
SET last_read_message_id = LEAST(conversation_read_cursors.last_read_message_id,
                                 EXCLUDED.last_read_message_id);

-- Members, counters and cursors of the copies go with them (ON DELETE CASCADE).
DELETE FROM conversations c
USING mair478_merge mg
WHERE c.id = mg.duplicate_id;

UPDATE conversations c
SET kind = 'direct', direct_user_low = d.user_low, direct_user_high = d.user_high
FROM mair478_direct d
WHERE c.id = d.conversation_id;

-- A participant who had left gets their row back, hidden.
INSERT INTO conversation_members (conversation_id, user_id, is_excluded)
SELECT c.id, p.user_id, TRUE
FROM conversations c
CROSS JOIN LATERAL (VALUES (c.direct_user_low), (c.direct_user_high)) AS p(user_id)
WHERE c.direct_user_low IS NOT NULL
ON CONFLICT (conversation_id, user_id) DO NOTHING;

-- Everything else is a group conversation.
UPDATE conversations
SET kind = 'group'
WHERE kind = 'direct' AND direct_user_low IS NULL;

---
-- Constraints
---
-- A direct conversation has its two distinct participants and no group; any
-- other kind has no participant pair.
ALTER TABLE conversations ADD CONSTRAINT chk_conversations_direct_pair CHECK (
    (kind = 'direct'
        AND group_id IS NULL
        AND direct_user_low IS NOT NULL
        AND direct_user_high IS NOT NULL
        AND direct_user_low < direct_user_high)
    OR (kind <> 'direct' AND direct_user_low IS NULL AND direct_user_high IS NULL)
);

ALTER TABLE conversations ADD CONSTRAINT uq_conversations_direct_pair
    UNIQUE (direct_user_low, direct_user_high);

-- Covers the second foreign key (the unique index covers the first one).
CREATE INDEX IF NOT EXISTS idx_conversations_direct_user_high
    ON conversations (direct_user_high) WHERE direct_user_high IS NOT NULL;
