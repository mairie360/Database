CREATE OR REPLACE FUNCTION fn_cleanup_unread_counters()
RETURNS TRIGGER AS $$
BEGIN
    -- Si la valeur est tombée à 0, on supprime la ligne
    IF NEW.unread_count <= 0 THEN
        DELETE FROM unread_counters
        WHERE user_id = NEW.user_id
          AND conversation_id = NEW.conversation_id;

        -- IMPORTANT: On retourne NULL pour annuler l'UPDATE sur la ligne supprimée
        -- cela évite des conflits avec l'opération de mise à jour en cours.
        RETURN NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_cleanup_unread_counters ON unread_counters;

CREATE TRIGGER tr_cleanup_unread_counters
    BEFORE UPDATE OF unread_count ON unread_counters
    FOR EACH ROW
    WHEN (NEW.unread_count <= 0)
    EXECUTE FUNCTION fn_cleanup_unread_counters();
