-- Project_API tasks/get_project_tasks/view.rs: tasks of a (busy) project, page 1
\set uid random_exponential(2, 20000, 3)
SELECT EXISTS(SELECT 1 FROM users WHERE id = :uid AND NOT COALESCE(is_archived, false)) AS is_user_active;
\set pid random_exponential(1, 2000, 3)
SELECT jsonb_build_object('total', count(*), 'items', COALESCE(jsonb_agg(to_jsonb(t) - 'rn' ORDER BY t.rn) FILTER (WHERE t.rn > 0::bigint AND t.rn <= 0::bigint + 50::bigint), '[]'::jsonb))
FROM (SELECT id, title, description, status, priority, created_at, assigned_to, due_date AT TIME ZONE 'UTC' AS due_date,
             COALESCE(custom_fields, '{}'::jsonb) AS custom_fields, row_number() OVER (ORDER BY created_at, id) AS rn
      FROM tasks WHERE project_id = :pid) t;
