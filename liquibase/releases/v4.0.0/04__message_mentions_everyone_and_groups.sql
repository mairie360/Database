-- Mentions of everyone and of groups (MAIR-1155, messaging V2), next to the mentions of agents
-- (message_mentions, rel-1.2.0):
--   * messages.mentions_everyone: the message mentions every member of the conversation (@everyone);
--   * message_group_mentions: the groups a message mentions; Message_API only accepts a group one
--     member of the conversation belongs to, and notifies the members of the group present in it.
-- Deleting the message or the group removes the mention.
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS mentions_everyone BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE message_group_mentions (
    message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    group_id   INT    NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    PRIMARY KEY (message_id, group_id)
);

-- Foreign key lookup when a group is deleted.
CREATE INDEX idx_message_group_mentions_group_id ON message_group_mentions (group_id);
