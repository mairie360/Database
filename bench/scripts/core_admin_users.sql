-- Core_API admin/list_users/view.rs: admin user list without search, any page
-- (MAIR-477, measured by the MAIR-474 load test). The ids of the page are read in the
-- order of idx_users_name_order (releases/v3.0.1), then only their rows.
\set uid random_exponential(2, 20000 * :scale, 3)
SELECT EXISTS(SELECT 1 FROM users WHERE id = :uid AND NOT COALESCE(is_archived, false)) AS is_user_active;
\set off random(0, 20000 * :scale - 20)
WITH page AS (
  SELECT o.id FROM users o
  ORDER BY o.last_name, o.first_name, o.id
  LIMIT 20 OFFSET :off)
SELECT to_jsonb(t) FROM (
  SELECT u.id, u.first_name, u.last_name, u.email, u.phone_number, u.phone_country,
    u.status, COALESCE(u.is_archived, false) AS is_archived,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name) ORDER BY r.name)
              FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = u.id), '[]'::jsonb) AS roles
  FROM page JOIN users u ON u.id = page.id
  ORDER BY u.last_name, u.first_name, u.id
) t;
SELECT COUNT(*) FROM users u;
