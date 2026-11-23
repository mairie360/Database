CREATE OR REPLACE FUNCTION fn_update_user_course_progress()
RETURNS TRIGGER AS $$
DECLARE
    v_course_id INT;
    v_total_modules INT;
    v_completed_modules INT;
BEGIN
    -- Course of the module
    SELECT course_id INTO v_course_id FROM course_modules WHERE id = NEW.module_id;

    -- Start the enrolment when needed; every module write is an activity of the agent (MAIR-1143).
    -- The activity is dated at write time (clock_timestamp(), not the transaction start) and never
    -- moves backwards: an older transaction committing last keeps the newer date.
    INSERT INTO user_courses (user_id, course_id, status, started_at, last_activity_at)
    VALUES (NEW.user_id, v_course_id, 'in_progress', CURRENT_TIMESTAMP, clock_timestamp()::TIMESTAMP)
    ON CONFLICT (user_id, course_id)
    DO UPDATE SET status = CASE WHEN user_courses.status = 'not_started' THEN 'in_progress'::progress_status
                                ELSE user_courses.status END,
                  last_activity_at = GREATEST(user_courses.last_activity_at, clock_timestamp()::TIMESTAMP);

    -- Modules of the course
    SELECT COUNT(*)::INT INTO v_total_modules FROM course_modules WHERE course_id = v_course_id;

    -- Completed ones
    SELECT COUNT(*)::INT INTO v_completed_modules
    FROM user_modules um
    JOIN course_modules cm ON um.module_id = cm.id
    WHERE um.user_id = NEW.user_id AND cm.course_id = v_course_id AND um.is_completed = TRUE;

    -- Status of the enrolment
    IF v_total_modules = v_completed_modules THEN
        UPDATE user_courses
        SET status = 'completed', completed_at = CURRENT_TIMESTAMP
        WHERE user_id = NEW.user_id AND course_id = v_course_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger
DROP TRIGGER IF EXISTS tr_after_user_module_update ON user_modules;
CREATE TRIGGER tr_after_user_module_update
    AFTER INSERT OR UPDATE ON user_modules
    FOR EACH ROW
    EXECUTE FUNCTION fn_update_user_course_progress();
