CREATE OR REPLACE FUNCTION fn_archive_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Suppression effective des liens de l'utilisateur archivé
    DELETE FROM sessions WHERE user_id = OLD.id;
    DELETE FROM project_members WHERE user_id = OLD.id;

    -- Désassignation des tâches
    UPDATE tasks SET assigned_to = NULL WHERE assigned_to = OLD.id;

    -- Suppression des compteurs non lus (si nécessaire)
    DELETE FROM unread_counters WHERE user_id = OLD.id;

    RETURN NULL;
    -- delete from group_members
    -- DELETE FROM group_members WHERE user_id = OLD.id;
    -- -- archive all access controls
    -- -- remove all calendar events where is owner
    -- DELETE FROM events WHERE owner_id = OLD.id;
    -- -- remove user_calendar_params
    -- DELETE FROM user_calendar_params WHERE user_id = OLD.id;
    -- -- remove from all calendar events where is not owner
    -- DELETE FROM event_members WHERE user_id = OLD.id;
    -- -- remove owner_id from all messages where is owner
    -- UPDATE messages SET owner_id = NULL WHERE owner_id = OLD.id;
    -- -- remove all unread counters
    -- DELETE FROM unread_counters WHERE user_id = OLD.id;
    -- -- remove all courses progress
    -- DELETE FROM courses_progress WHERE user_id = OLD.id;
    -- -- remove all modules progress
    -- DELETE FROM modules_progress WHERE user_id = OLD.id;
    -- -- remove all project_members
    -- DELETE FROM project_members WHERE user_id = OLD.id;
    -- -- remove from all tasks assigned_to
    -- UPDATE tasks SET assigned_to = NULL WHERE assigned_to = OLD.id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- 2. Action : On nettoie les ressources APRÈS l'UPDATE réussi
DROP TRIGGER IF EXISTS tr_archive_user_cleanup ON users;
CREATE TRIGGER tr_archive_user_cleanup
    AFTER UPDATE OF is_archived ON users
    FOR EACH ROW
    WHEN (NEW.is_archived IS TRUE AND OLD.is_archived IS FALSE)
    EXECUTE FUNCTION fn_archive_user();
