-- Reactions to a message (MAIR-1155, messaging V2): one row per message, agent and emoji. The primary
-- key makes a reaction idempotent: Message_API adds it with ON CONFLICT DO NOTHING, so two concurrent
-- adds of the same reaction leave one row. Deleting the message or the account removes its reactions.
CREATE TABLE message_reactions (
    message_id BIGINT      NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id    INT         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    emoji      VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (message_id, user_id, emoji),
    -- An emoji is 1 to 32 characters (skin tones and ZWJ sequences are several code points), without
    -- whitespace or control character.
    CONSTRAINT chk_message_reactions_emoji
        CHECK (char_length(emoji) BETWEEN 1 AND 32 AND emoji !~ '[[:space:]\x01-\x1f\x7f]')
);

-- Foreign key lookup (erasure, account deletion) and the reactions of an agent.
CREATE INDEX idx_message_reactions_user_id ON message_reactions (user_id);
