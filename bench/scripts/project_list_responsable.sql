-- Same query as project_list.sql for a 'Responsable' (user id multiple of 200): the group branch runs
\set r random(1, 99)
\set uid (:r * 200)
SELECT EXISTS(SELECT 1 FROM users WHERE id = :uid AND NOT COALESCE(is_archived, false)) AS is_user_active;
SELECT jsonb_build_object('total', count(*), 'items', COALESCE(jsonb_agg(to_jsonb(t) - 'rn' ORDER BY t.rn) FILTER (WHERE t.rn > 0::bigint AND t.rn <= 0::bigint + 20::bigint), '[]'::jsonb))
FROM (SELECT p.id, p.title, p.description, p.status, row_number() OVER (ORDER BY p.created_at DESC NULLS LAST, p.id DESC) AS rn
      FROM projects p WHERE
  (EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = :uid AND r.name IN ('Admin','Maire'))
   OR p.owner_id = :uid
   OR EXISTS (SELECT 1 FROM project_members pm WHERE pm.project_id = p.id AND pm.user_id = :uid)
   OR (EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = :uid AND r.name = 'Responsable')
       AND EXISTS (SELECT 1 FROM group_members mine JOIN group_members team ON team.group_id = mine.group_id
                   WHERE mine.user_id = :uid AND (team.user_id = p.owner_id
                     OR EXISTS (SELECT 1 FROM project_members team_member WHERE team_member.project_id = p.id AND team_member.user_id = team.user_id)))))
) t;
