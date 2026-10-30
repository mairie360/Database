-- MAIR-564: one role per user (user_roles_pkey is the user id). Guest is the placeholder
-- given by tr_users_default_role_guest to an account created without a role, often in a
-- transaction committed before its real role is written (registration, then a grant by an
-- administrator; the mairie360_api_lib test fixtures). Inserting another role for that
-- account replaces the Guest row instead of failing; any other second role is still refused
-- with a unique violation (23505). Changing a role on purpose is an UPDATE, or Core_API's
-- `INSERT ... ON CONFLICT (user_id) DO UPDATE`.
--
-- BEFORE INSERT row triggers run before the conflict check of INSERT ... ON CONFLICT, so
-- `ON CONFLICT DO NOTHING` writers get the new role too.
CREATE OR REPLACE FUNCTION fn_replace_default_role()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM user_roles ur
    USING roles r
    WHERE ur.user_id = NEW.user_id
      AND ur.role_id = r.id
      AND r.name = 'Guest'
      AND ur.role_id <> NEW.role_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_user_roles_replace_default ON user_roles;
CREATE TRIGGER tr_user_roles_replace_default
    BEFORE INSERT ON user_roles
    FOR EACH ROW
    EXECUTE FUNCTION fn_replace_default_role();
