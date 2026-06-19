-- Fonction pour supprimer les sessions actives si l'utilisateur est archivé
CREATE OR REPLACE FUNCTION fn_logout_user_on_archive()
RETURNS TRIGGER AS $$
BEGIN
    -- Si on passe de non-archivé à archivé
    IF (OLD.is_archived = FALSE AND NEW.is_archived = TRUE) THEN
        DELETE FROM sessions WHERE user_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attachement du trigger sur la table users
DROP TRIGGER IF EXISTS tr_05_logout_on_archive ON users;
CREATE TRIGGER tr_05_logout_on_archive
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION fn_logout_user_on_archive();
