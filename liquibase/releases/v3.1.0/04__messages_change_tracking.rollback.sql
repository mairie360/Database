DROP TRIGGER IF EXISTS tr_after_message_change ON messages;
DROP TRIGGER IF EXISTS tr_before_message_track ON messages;
DROP FUNCTION IF EXISTS fn_touch_conversation_activity();
DROP FUNCTION IF EXISTS fn_track_message_change();
DROP INDEX IF EXISTS idx_messages_conversation_updated;
ALTER TABLE conversations DROP COLUMN IF EXISTS last_activity_at;
-- Tombstones did not exist before: remove them with the columns.
DELETE FROM messages WHERE deleted_at IS NOT NULL;
ALTER TABLE messages
    DROP COLUMN IF EXISTS deleted_at,
    DROP COLUMN IF EXISTS edited_at,
    DROP COLUMN IF EXISTS updated_at;
