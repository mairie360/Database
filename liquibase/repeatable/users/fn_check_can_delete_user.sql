CREATE OR REPLACE FUNCTION fn_check_can_delete_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Utilisation de EXISTS pour la performance
    IF EXISTS (SELECT 1 FROM groups WHERE owner_id = OLD.id) THEN
        RAISE EXCEPTION 'Utilisateur % est propriétaire de groupes.', OLD.id
        USING ERRCODE = 'restrict_violation';
    END IF;

    IF EXISTS (SELECT 1 FROM events WHERE owner_id = OLD.id) THEN
        RAISE EXCEPTION 'Utilisateur % est propriétaire d''événements.', OLD.id
        USING ERRCODE = 'restrict_violation';
    END IF;

    IF EXISTS (SELECT 1 FROM projects WHERE owner_id = OLD.id) THEN
        RAISE EXCEPTION 'Utilisateur % est propriétaire de projets.', OLD.id
        USING ERRCODE = 'restrict_violation';
    END IF;

    -- On retourne NEW pour valider le passage à is_archived = TRUE
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 1. Validation : On vérifie les dépendances AVANT l'UPDATE
DROP TRIGGER IF EXISTS tr_validate_archive_user ON users;
CREATE TRIGGER tr_validate_archive_user
    BEFORE UPDATE OF is_archived ON users
    FOR EACH ROW
    WHEN (NEW.is_archived IS TRUE AND OLD.is_archived IS FALSE)
    EXECUTE FUNCTION fn_check_can_delete_user();
