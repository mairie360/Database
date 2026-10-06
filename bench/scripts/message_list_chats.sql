-- Message_API get_chats/view.rs: conversations of a user with unread counts
\set uid random_exponential(2, 20000, 3)
SELECT EXISTS(SELECT 1 FROM users WHERE id = :uid AND NOT COALESCE(is_archived, false)) AS is_user_active;
SELECT to_jsonb(t) FROM (
  SELECT c.id, c.title, COALESCE(uc.unread_count, 0) AS unread_count
  FROM conversations c
  INNER JOIN conversation_members cm ON c.id = cm.conversation_id
  LEFT JOIN unread_counters uc ON c.id = uc.conversation_id AND uc.user_id = cm.user_id
  WHERE cm.user_id = :uid AND cm.is_excluded = FALSE
  ORDER BY c.created_at DESC, c.id DESC
  LIMIT 21 OFFSET 0) t;
