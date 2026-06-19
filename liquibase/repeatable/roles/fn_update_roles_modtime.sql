-- Mise à jour du timestamp updated_at
DROP TRIGGER IF EXISTS update_roles_modtime ON roles;
CREATE TRIGGER update_roles_modtime
    BEFORE UPDATE ON roles
    FOR EACH ROW
    EXECUTE PROCEDURE update_updated_at_column();
