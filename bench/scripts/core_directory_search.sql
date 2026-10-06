-- Core_API users/list_directory/view.rs: directory search by name
\set uid random_exponential(2, 20000, 3)
SELECT EXISTS(SELECT 1 FROM users WHERE id = :uid AND NOT COALESCE(is_archived, false)) AS is_user_active;
\set n random(1, 5000)
SELECT to_jsonb(t) FROM (
  SELECT u.id, u.first_name, u.last_name, u.email,
    COALESCE((SELECT jsonb_agg(DISTINCT r.name) FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = u.id), '[]'::jsonb) AS roles,
    COALESCE((SELECT jsonb_agg(DISTINCT gm.group_id) FROM group_members gm WHERE gm.user_id = u.id), '[]'::jsonb) AS group_ids
  FROM users u
  WHERE COALESCE(u.is_archived, false) = false
    AND (NULLIF('Last' || :n, '') IS NULL OR u.first_name ILIKE '%' || ('Last' || :n) || '%' OR u.last_name ILIKE '%' || ('Last' || :n) || '%'
         OR concat_ws(' ', u.first_name, u.last_name) ILIKE '%' || ('Last' || :n) || '%' OR u.email ILIKE '%' || ('Last' || :n) || '%')
  ORDER BY u.last_name, u.first_name, u.id
  LIMIT 20) t;
