-- System notes did not exist before: an older Message_API would show them as empty messages.
DELETE FROM messages WHERE kind = 'system';
ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS chk_messages_system_event_shape,
    DROP CONSTRAINT IF EXISTS chk_messages_system_event,
    DROP CONSTRAINT IF EXISTS chk_messages_kind,
    DROP COLUMN IF EXISTS system_event,
    DROP COLUMN IF EXISTS kind;
