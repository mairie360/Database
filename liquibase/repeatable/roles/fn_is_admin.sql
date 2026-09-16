-- Vrai uniquement si l'utilisateur possède le rôle Admin (nom protégé par
-- protect_role_names). Ne pas se contenter de l'existence d'un rôle : depuis
-- tr_users_default_role_guest, tout utilisateur en a au moins un (Guest).
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
        WHERE ur.user_id = p_user_id
          AND r.name = 'Admin'
    );
END;
$$ LANGUAGE plpgsql;
