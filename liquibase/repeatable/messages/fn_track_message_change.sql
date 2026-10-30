-- MAIR-524: change tracking of the messages, for the reads since a cursor of Message_API.
--
-- fn_track_message_change (BEFORE INSERT OR UPDATE on messages) stamps updated_at with the
-- clock time after taking the conversation lock (pg_advisory_xact_lock(360, conversation),
-- the one of fn_before_message_insert and fn_acknowledge_read, held until commit): within a
-- conversation, a change committed later always has a later updated_at, so a reader that saw
-- the changes up to T misses none of those it has not seen. The trigger name sorts after
-- tr_before_message_insert, which takes the lock first on an insert.
--   * an edit of the content sets edited_at;
--   * deleting a message is an UPDATE setting deleted_at (Message_API), which also empties the
--     content: the tombstone keeps no personal data.
-- fn_touch_conversation_activity (AFTER) moves conversations.last_activity_at forward.
CREATE OR REPLACE FUNCTION fn_track_message_change()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(360, NEW.conversation_id);
    NEW.updated_at := clock_timestamp();

    IF TG_OP = 'UPDATE' THEN
        IF NEW.deleted_at IS NOT NULL THEN
            NEW.content := '';
            NEW.deleted_at := COALESCE(OLD.deleted_at, NEW.updated_at);
        ELSIF NEW.content IS DISTINCT FROM OLD.content THEN
            NEW.edited_at := NEW.updated_at;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION fn_touch_conversation_activity()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations
    SET last_activity_at = GREATEST(last_activity_at, NEW.updated_at)
    WHERE id = NEW.conversation_id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS tr_before_message_track ON messages;
CREATE TRIGGER tr_before_message_track
    BEFORE INSERT OR UPDATE ON messages
    FOR EACH ROW
    EXECUTE FUNCTION fn_track_message_change();

DROP TRIGGER IF EXISTS tr_after_message_change ON messages;
CREATE TRIGGER tr_after_message_change
    AFTER INSERT OR UPDATE ON messages
    FOR EACH ROW
    EXECUTE FUNCTION fn_touch_conversation_activity();
