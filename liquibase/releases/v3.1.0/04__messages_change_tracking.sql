-- MAIR-524: incremental reads of Message_API (messages and conversations changed since a
-- cursor) instead of reloading every conversation every 2 seconds.
--
--   * messages.updated_at: last change of the message (sent, edited, deleted), set by
--     fn_track_message_change (repeatable/messages) under the conversation lock, so within a
--     conversation a change committed later always has a later updated_at.
--   * messages.edited_at: last edit of the content, NULL when never edited.
--   * messages.deleted_at: a deleted message stays as a tombstone (content emptied) so that a
--     reader since a cursor learns about the deletion. The lists skip tombstones.
--   * conversations.last_activity_at: last message change of the conversation (or its
--     creation), for the conversations changed since a cursor.
--
-- No backfill: the existing rows take the migration time (fast default, no table rewrite), so a
-- cursor older than the deployment returns them once.
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- Changes of a conversation since a cursor, in cursor order: (updated_at, id) > (since, since_id).
CREATE INDEX IF NOT EXISTS idx_messages_conversation_updated
    ON messages (conversation_id, updated_at, id);
