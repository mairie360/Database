-- MAIR-394: trace of the moderation done by administrators in Message_API.
--
-- One row each time an administrator deletes a message written by someone
-- else, or deletes a whole conversation. The row keeps a snapshot (message
-- content or conversation title) because the deleted rows are gone.
-- No foreign key on purpose: the log outlives the conversation, the message
-- and the accounts it names. message_api may only INSERT (api_grants.sql).
CREATE TABLE IF NOT EXISTS messaging_moderation_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    action VARCHAR(32) NOT NULL,
    conversation_id INT NOT NULL,
    message_id BIGINT,
    target_user_id INT,
    content TEXT,
    performed_by INT NOT NULL,
    performed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_messaging_moderation_log_action
        CHECK (action IN ('DELETE_MESSAGE', 'DELETE_CONVERSATION')),
    CONSTRAINT chk_messaging_moderation_log_message
        CHECK ((action = 'DELETE_MESSAGE') = (message_id IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_messaging_moderation_log_conversation
    ON messaging_moderation_log (conversation_id, performed_at);
CREATE INDEX IF NOT EXISTS idx_messaging_moderation_log_performed_by
    ON messaging_moderation_log (performed_by, performed_at);
