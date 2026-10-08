-- MAIR-269: explicit read acknowledgement.
--
-- One cursor per (agent, conversation): the highest message id the agent has
-- acknowledged as displayed. It lives in its own table because
-- unread_counters rows are deleted as soon as they reach zero
-- (fn_cleanup_unread_counters), which would forget the cursor and let a stale
-- acknowledgement move it backwards.
--
-- No foreign key on last_read_message_id: a deleted message is still a valid
-- boundary. Existing agents have no cursor yet: their unread_counters row is
-- left untouched and is recomputed by the first fn_acknowledge_read call.
CREATE TABLE conversation_read_cursors (
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id INT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    last_read_message_id BIGINT NOT NULL,
    PRIMARY KEY (user_id, conversation_id)
);

CREATE INDEX IF NOT EXISTS idx_conversation_read_cursors_conversation_id
    ON conversation_read_cursors (conversation_id);

-- Unread recount: messages of a conversation after the cursor.
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_id
    ON messages (conversation_id, id);
