-- Protection des noms de rôles systèmes (Modification)
CREATE OR REPLACE FUNCTION protect_role_names()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.can_be_deleted = FALSE AND NEW.name <> OLD.name THEN
        RAISE EXCEPTION 'Modification interdite : le nom du rôle "%" est réservé.', OLD.name;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS trigger_protect_role_names ON roles;
CREATE TRIGGER trigger_protect_role_names
    BEFORE UPDATE ON roles
    FOR EACH ROW
    EXECUTE PROCEDURE protect_role_names();
