CREATE OR REPLACE FUNCTION fn_auto_increment_unread_counter()
RETURNS TRIGGER AS $$
DECLARE
    v_group_id INT;
BEGIN
    SELECT group_id INTO v_group_id
    FROM conversations
    WHERE id = NEW.conversation_id;

    IF v_group_id IS NOT NULL THEN
        -- Chat de groupe
        INSERT INTO unread_counters (conversation_id, user_id, unread_count)
        SELECT NEW.conversation_id, gu.user_id, 1
        FROM group_members gu
        WHERE gu.group_id = v_group_id
          AND gu.user_id != NEW.sender_id
          AND gu.user_id NOT IN (
              SELECT user_id FROM conversation_members
              WHERE conversation_id = NEW.conversation_id AND is_excluded = TRUE
          )
        ON CONFLICT (conversation_id, user_id)
        DO UPDATE SET unread_count = unread_counters.unread_count + 1;

    ELSE
        -- Chat privé
        INSERT INTO unread_counters (conversation_id, user_id, unread_count)
        SELECT NEW.conversation_id, cm.user_id, 1
        FROM conversation_members cm
        WHERE cm.conversation_id = NEW.conversation_id
          AND cm.user_id != NEW.sender_id
          AND cm.is_excluded = FALSE
        ON CONFLICT (conversation_id, user_id)
        DO UPDATE SET unread_count = unread_counters.unread_count + 1;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_after_message_insert ON messages;
CREATE TRIGGER tr_after_message_insert
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION fn_auto_increment_unread_counter();
