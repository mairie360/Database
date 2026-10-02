-- Vrai uniquement si l'utilisateur possède le rôle Admin (nom protégé par
-- protect_role_names). Ne pas se contenter de l'existence d'un rôle : depuis
-- tr_users_default_role_guest, tout utilisateur en a au moins un (Guest).
--
-- An archived account is never admin (MAIR-413): archiving keeps its
-- user_roles so that restore_user() gives its rights back.
--
-- SECURITY DEFINER: every API calls it (API_lib AdminMiddleware) without
-- necessarily reading user_roles / roles (MAIR-114).
CREATE OR REPLACE FUNCTION is_admin(
    p_user_id INT
)
RETURNS BOOLEAN
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM user_roles ur
        JOIN roles r ON r.id = ur.role_id
        JOIN users u ON u.id = ur.user_id
        WHERE ur.user_id = p_user_id
          AND r.name = 'Admin'
          AND u.is_archived IS NOT TRUE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
