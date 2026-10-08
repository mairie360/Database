-- MAIR-394: Message_API audit fixes.
--
-- conversations.created_by: the agent who created the conversation. Message_API
-- only lets the creator (or an administrator) add members or remove someone
-- else; any member may still leave. NULL once the creator's account is
-- deleted, and for conversations without any member left to backfill from:
-- only administrators manage those.
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS created_by INT REFERENCES users(id) ON DELETE SET NULL;

-- Backfill: the earliest member of each existing conversation.
UPDATE conversations c
SET created_by = (
    SELECT m.user_id
    FROM conversation_members m
    WHERE m.conversation_id = c.id
    ORDER BY m.joined_at, m.user_id
    LIMIT 1
)
WHERE c.created_by IS NULL;

CREATE INDEX IF NOT EXISTS idx_conversations_created_by
    ON conversations (created_by) WHERE created_by IS NOT NULL;

-- messages.reply_to_id: the message this one answers (the API's `citation`).
-- The composite foreign key makes a reply point to a message of the same
-- conversation; deleting the quoted message only clears reply_to_id.
ALTER TABLE messages
    ADD CONSTRAINT uq_messages_conversation_id_id UNIQUE (conversation_id, id);

ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to_id BIGINT;

ALTER TABLE messages
    ADD CONSTRAINT fk_messages_reply_to
    FOREIGN KEY (conversation_id, reply_to_id)
    REFERENCES messages (conversation_id, id)
    ON DELETE SET NULL (reply_to_id);

-- Covers the foreign key (lookup of the replies when a message is deleted).
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_reply_to_id
    ON messages (conversation_id, reply_to_id) WHERE reply_to_id IS NOT NULL;
