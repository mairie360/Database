-- Protection des rôles systèmes (Suppression)
CREATE OR REPLACE FUNCTION protect_critical_roles()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.can_be_deleted = FALSE THEN
        RAISE EXCEPTION 'Suppression impossible : le rôle "%" est critique pour le système.', OLD.name;
    END IF;
    RETURN OLD;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS trigger_protect_roles ON roles;
CREATE TRIGGER trigger_protect_roles
    BEFORE DELETE ON roles
    FOR EACH ROW
    EXECUTE PROCEDURE protect_critical_roles();
