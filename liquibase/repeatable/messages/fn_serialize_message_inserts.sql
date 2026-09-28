-- MAIR-269: serialize message inserts per conversation and hand out ids in
-- commit order.
--
-- The lock is transaction-scoped, so it is held until the sender commits, and
-- fn_acknowledge_read takes the same one. Consequences:
--   * an acknowledgement never runs while a send is in flight, and a send
--     never lands in the middle of one;
--   * the id is drawn after the lock, so a message committed later always has
--     a higher id than one committed earlier: a reader that displayed message
--     N has necessarily displayed everything below N.
-- 360 is the lock namespace (first key), the conversation id the second one.
CREATE OR REPLACE FUNCTION fn_before_message_insert()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(360, NEW.conversation_id);

    IF NEW.id IS NULL THEN
        NEW.id := nextval(pg_get_serial_sequence('messages', 'id'));
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_before_message_insert ON messages;

CREATE TRIGGER tr_before_message_insert
    BEFORE INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION fn_before_message_insert();
