-- MAIR-269: messages.id is now assigned by tr_before_message_insert, after the
-- per-conversation lock is taken (see messages/fn_serialize_message_inserts.sql),
-- so that within a conversation ids are handed out in commit order. A single
-- "read until message id" cursor is only sound if no lower id can commit after
-- a higher one has been displayed.
--
-- The sequence stays owned by the column (the API roles still get USAGE on it
-- through the grants loop); only the column default is dropped. Explicit ids
-- (seeds, tests) are kept as is by the trigger.
ALTER TABLE messages ALTER COLUMN id DROP DEFAULT;
