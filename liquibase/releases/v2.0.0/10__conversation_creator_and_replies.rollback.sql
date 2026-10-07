-- Rollback of 03__conversation_creator_and_replies.sql (MAIR-394).
-- The creator and the reply links are lost.
DROP INDEX IF EXISTS idx_messages_conversation_id_reply_to_id;
ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS fk_messages_reply_to,
    DROP COLUMN IF EXISTS reply_to_id,
    DROP CONSTRAINT IF EXISTS uq_messages_conversation_id_id;

DROP INDEX IF EXISTS idx_conversations_created_by;
ALTER TABLE conversations DROP COLUMN IF EXISTS created_by;
