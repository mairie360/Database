-- Filet de sécurité : un utilisateur qui se retrouve sans aucun rôle se voit
-- attribuer le rôle Guest. Le trigger est un CONSTRAINT TRIGGER DEFERRABLE
-- INITIALLY DEFERRED : il ne s'exécute qu'à la fin de la transaction, donc
-- une fois que create_user() (ou tout autre code de la même transaction
-- assignant un rôle) a terminé. Cela évite d'attribuer Guest prématurément
-- entre l'INSERT dans users et l'INSERT dans user_roles.
CREATE OR REPLACE FUNCTION fn_assign_default_role()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = NEW.id) THEN
        INSERT INTO user_roles (user_id, role_id)
        SELECT NEW.id, id FROM roles WHERE name = 'Guest'
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_users_default_role_guest ON users;
CREATE CONSTRAINT TRIGGER tr_users_default_role_guest
    AFTER INSERT ON users
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION fn_assign_default_role();
