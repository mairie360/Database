-- API_lib RightMiddleware on /events/{id}: check_access writes access_logs
\set uid random_exponential(2, 20000 * :scale, 3)
SELECT EXISTS(SELECT 1 FROM users WHERE id = :uid AND NOT COALESCE(is_archived, false)) AS is_user_active;
\set eid random(1, 200000 * :scale)
SELECT check_access(:uid, 'events', 'read', :eid);
