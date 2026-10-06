-- Message_API access/view.rs + get_chat/view.rs: open a (busy) conversation, newest page
\set uid random_exponential(2, 20000 * :scale, 3)
SELECT EXISTS(SELECT 1 FROM users WHERE id = :uid AND NOT COALESCE(is_archived, false)) AS is_user_active;
\set cid random_exponential(1, 20000 * :scale, 5)
SELECT jsonb_build_object(
 'chat_exists', EXISTS(SELECT 1 FROM conversations WHERE id = :cid),
 'is_member', EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id = :cid AND user_id = :uid AND is_excluded = FALSE),
 'is_creator', EXISTS(SELECT 1 FROM conversations WHERE id = :cid AND created_by = :uid),
 'is_admin', is_admin(:uid));
SELECT to_jsonb(t) FROM (
  SELECT id, owner_id, content, created_at, reply_to_id FROM messages
  WHERE conversation_id = :cid AND (0::bigint = 0 OR id < 0::bigint)
  ORDER BY id DESC LIMIT 50) t;
