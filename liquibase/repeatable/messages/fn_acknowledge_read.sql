-- MAIR-269: explicit read acknowledgement.
--
-- Marks the conversation as read by p_user_id up to p_message_id and returns
-- the real number of messages still unread by that agent.
--   * NULL when p_message_id does not belong to p_conversation_id.
--   * Idempotent, and monotonic: the cursor only moves forward, so a repeated
--     or stale acknowledgement returns the current count and changes nothing.
--   * The count is recomputed from the cursor (messages after it, written by
--     someone else) and only counts for agents who receive the conversation's
--     notifications, like fn_auto_increment_unread_counter: group members of a
--     group conversation, members of a direct one, never an excluded agent.
--   * Messages sent after the cursor are never cleared: the conversation lock
--     (see fn_before_message_insert) makes an acknowledgement and a send
--     strictly ordered, and the send's trigger increments the counter after
--     the acknowledgement has written it.
-- The caller must check beforehand that the agent may access the conversation.
CREATE OR REPLACE FUNCTION fn_acknowledge_read(
    p_user_id INT,
    p_conversation_id INT,
    p_message_id BIGINT
)
RETURNS INT AS $$
DECLARE
    v_group_id INT;
    v_cursor BIGINT;
    v_is_recipient BOOLEAN;
    v_unread INT;
BEGIN
    PERFORM pg_advisory_xact_lock(360, p_conversation_id);

    IF NOT EXISTS (
        SELECT 1 FROM messages
        WHERE id = p_message_id AND conversation_id = p_conversation_id
    ) THEN
        RETURN NULL;
    END IF;

    INSERT INTO conversation_read_cursors AS c (user_id, conversation_id, last_read_message_id)
    VALUES (p_user_id, p_conversation_id, p_message_id)
    ON CONFLICT (user_id, conversation_id)
    DO UPDATE SET last_read_message_id = GREATEST(c.last_read_message_id, EXCLUDED.last_read_message_id)
    RETURNING c.last_read_message_id INTO v_cursor;

    SELECT group_id INTO v_group_id
    FROM conversations
    WHERE id = p_conversation_id;

    IF v_group_id IS NOT NULL THEN
        v_is_recipient :=
            EXISTS (
                SELECT 1 FROM group_members
                WHERE group_id = v_group_id AND user_id = p_user_id
            )
            AND NOT EXISTS (
                SELECT 1 FROM conversation_members
                WHERE conversation_id = p_conversation_id
                  AND user_id = p_user_id
                  AND is_excluded = TRUE
            );
    ELSE
        v_is_recipient := EXISTS (
            SELECT 1 FROM conversation_members
            WHERE conversation_id = p_conversation_id
              AND user_id = p_user_id
              AND is_excluded = FALSE
        );
    END IF;

    IF v_is_recipient THEN
        SELECT count(*)::INT INTO v_unread
        FROM messages
        WHERE conversation_id = p_conversation_id
          AND id > v_cursor
          AND owner_id IS DISTINCT FROM p_user_id;
    ELSE
        v_unread := 0;
    END IF;

    -- unread_counters has no row for a zero count (fn_cleanup_unread_counters).
    IF v_unread > 0 THEN
        INSERT INTO unread_counters (user_id, conversation_id, unread_count)
        VALUES (p_user_id, p_conversation_id, v_unread)
        ON CONFLICT (user_id, conversation_id)
        DO UPDATE SET unread_count = EXCLUDED.unread_count;
    ELSE
        DELETE FROM unread_counters
        WHERE user_id = p_user_id AND conversation_id = p_conversation_id;
    END IF;

    RETURN v_unread;
END;
$$ LANGUAGE plpgsql;
