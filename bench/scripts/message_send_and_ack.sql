-- Message_API add_message_to_chat + acknowledge_read: a member posts, another reads
\set cid random_exponential(1, 20000 * :scale, 5)
SELECT COALESCE(min(user_id), 2) AS sender, COALESCE(max(user_id), 2) AS reader
FROM conversation_members WHERE conversation_id = :cid \gset
SELECT EXISTS(SELECT 1 FROM users WHERE id = :sender AND NOT COALESCE(is_archived, false)) AS is_user_active;
INSERT INTO messages (conversation_id, owner_id, content, reply_to_id)
VALUES (:cid, :sender, 'bench message', NULLIF(0::bigint, 0)) RETURNING id AS mid \gset
SELECT unread FROM (SELECT fn_acknowledge_read(:reader, :cid, :mid) AS unread) ack WHERE unread IS NOT NULL;
