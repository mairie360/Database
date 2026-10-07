-- Core_API users/list_directory/view.rs: directory search by name, matches collected
-- first (MATERIALIZED) through the search expression of releases/v3.0.1, so the name order
-- index is not walked (MAIR-477)
\set uid random_exponential(2, 20000 * :scale, 3)
SELECT EXISTS(SELECT 1 FROM users WHERE id = :uid AND NOT COALESCE(is_archived, false)) AS is_user_active;
\set n random(1, 5000 * :scale)
WITH matched AS MATERIALIZED (
  SELECT u.id, u.first_name, u.last_name, u.email FROM users u
  WHERE COALESCE(u.is_archived, false) = false
    AND (NULLIF('Last' || :n, '') IS NULL
         OR lower(u.first_name || ' ' || u.last_name || chr(31) || u.last_name || ' ' || u.first_name
                  || chr(31) || u.email) LIKE '%' || lower('Last' || :n) || '%')
), page AS (
  SELECT * FROM matched ORDER BY last_name, first_name, id LIMIT 20
)
SELECT to_jsonb(t) FROM (
  SELECT p.id, p.first_name, p.last_name, p.email,
    COALESCE((SELECT jsonb_agg(DISTINCT r.name) FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = p.id), '[]'::jsonb) AS roles,
    COALESCE((SELECT jsonb_agg(DISTINCT gm.group_id) FROM group_members gm WHERE gm.user_id = p.id), '[]'::jsonb) AS group_ids
  FROM page p
  ORDER BY p.last_name, p.first_name, p.id) t;
