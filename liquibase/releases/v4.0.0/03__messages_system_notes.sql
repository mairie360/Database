-- System notes of a conversation (MAIR-1155, messaging V2): Message_API writes one in the transaction
-- that adds members, removes one or lets one leave, so the history shows who changed the membership.
--
--   * messages.kind: 'user' (written by an agent, the existing rows) or 'system' (a note);
--   * messages.system_event: what the note says, set for a note only:
--     {"action": "members_added" | "member_removed" | "member_left", "actor_id": <int>,
--      "user_ids": [<int>, ...]}. owner_id is the actor and content is '' (messages.content has no
--     non-empty CHECK, so nothing changes there).
-- A note is not an unread message: fn_auto_increment_unread_counter and fn_acknowledge_read
-- (repeatable/messages/) skip kind = 'system'.
--
-- Expand only: both columns have a default, the APIs of the release in prod insert 'user' messages
-- without knowing them.
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS kind VARCHAR(16) NOT NULL DEFAULT 'user',
    ADD COLUMN IF NOT EXISTS system_event JSONB;

ALTER TABLE messages ADD CONSTRAINT chk_messages_kind
    CHECK (kind IN ('user', 'system'));

ALTER TABLE messages ADD CONSTRAINT chk_messages_system_event
    CHECK ((kind = 'system') = (system_event IS NOT NULL));

ALTER TABLE messages ADD CONSTRAINT chk_messages_system_event_shape
    CHECK (
        system_event IS NULL
        OR (
            jsonb_typeof(system_event) = 'object'
            AND system_event ->> 'action' IN ('members_added', 'member_removed', 'member_left')
            AND jsonb_typeof(system_event -> 'actor_id') = 'number'
            AND jsonb_typeof(system_event -> 'user_ids') = 'array'
        )
    );
