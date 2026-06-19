CREATE OR REPLACE FUNCTION fn_update_user_course_progress()
RETURNS TRIGGER AS $$
DECLARE
    v_course_id INT;
    v_total_modules INT;
    v_completed_modules INT;
BEGIN
    -- Retrouver la formation parente
    SELECT course_id INTO v_course_id FROM course_modules WHERE id = NEW.module_id;

    -- Initialisation de la progression si nécessaire
    INSERT INTO user_courses (user_id, course_id, status, started_at)
    VALUES (NEW.user_id, v_course_id, 'in_progress', CURRENT_TIMESTAMP)
    ON CONFLICT (user_id, course_id)
    DO UPDATE SET status = 'in_progress' WHERE user_courses.status = 'not_started';

    -- Compter les modules
    SELECT COUNT(*)::INT INTO v_total_modules FROM course_modules WHERE course_id = v_course_id;

    -- Compter les validés
    SELECT COUNT(*)::INT INTO v_completed_modules
    FROM user_modules um
    JOIN course_modules cm ON um.module_id = cm.id
    WHERE um.user_id = NEW.user_id AND cm.course_id = v_course_id AND um.is_completed = TRUE;

    -- Mise à jour statut global
    IF v_total_modules = v_completed_modules THEN
        UPDATE user_courses
        SET status = 'completed', completed_at = CURRENT_TIMESTAMP
        WHERE user_id = NEW.user_id AND course_id = v_course_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attachement du trigger
DROP TRIGGER IF EXISTS tr_after_user_module_update ON user_modules;
CREATE TRIGGER tr_after_user_module_update
    AFTER INSERT OR UPDATE ON user_modules
    FOR EACH ROW
    EXECUTE FUNCTION fn_update_user_course_progress();
