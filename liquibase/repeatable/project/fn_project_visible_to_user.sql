-- project_visible_to_user(user, project) (MAIR-1166): whether a user sees a project, the rule of
-- Project_API (`project_visible_to_user_sql!` in its src/database/project/mod.rs; keep both in step):
-- - Admin or Maire: every project;
-- - Responsable: their projects, those they are a member of, and those of their team (a member of
--   one of their groups owns it or is a member of it);
-- - other roles: the projects they own or are a member of;
-- - whatever the role, a project linked to one of their groups (`project_groups`).
-- An archived or suspended account sees nothing. Message_API checks the project and task links of a
-- message with it: SECURITY DEFINER, so message_api reads no RBAC nor project table.
DROP FUNCTION IF EXISTS project_visible_to_user(INT, INT);
CREATE FUNCTION project_visible_to_user(p_user_id INT, p_project_id INT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (SELECT 1 FROM projects WHERE id = p_project_id)
       AND EXISTS (SELECT 1 FROM users u WHERE u.id = p_user_id
                    AND u.is_archived IS NOT TRUE AND u.status IS DISTINCT FROM 'suspended')
       AND (
            EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
                     WHERE ur.user_id = p_user_id AND r.name IN ('Admin', 'Maire'))
         OR EXISTS (SELECT 1 FROM projects own WHERE own.id = p_project_id AND own.owner_id = p_user_id)
         OR EXISTS (SELECT 1 FROM project_members pm
                     WHERE pm.project_id = p_project_id AND pm.user_id = p_user_id)
         OR EXISTS (SELECT 1 FROM group_members mine
                      JOIN project_groups linked ON linked.group_id = mine.group_id
                     WHERE mine.user_id = p_user_id AND linked.project_id = p_project_id)
         OR (EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
                      WHERE ur.user_id = p_user_id AND r.name = 'Responsable')
             AND EXISTS (SELECT 1 FROM group_members mine
                           JOIN group_members team ON team.group_id = mine.group_id
                          WHERE mine.user_id = p_user_id
                            AND (EXISTS (SELECT 1 FROM projects tp
                                          WHERE tp.id = p_project_id AND tp.owner_id = team.user_id)
                                 OR EXISTS (SELECT 1 FROM project_members tm
                                             WHERE tm.project_id = p_project_id AND tm.user_id = team.user_id))))
       );
$$;

REVOKE ALL ON FUNCTION project_visible_to_user(INT, INT) FROM PUBLIC;
