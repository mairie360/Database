-- Trigger: archiving of the completed tasks (MAIR-502).
--
-- A task is archived as soon as it becomes `completed` (tasks.archived_at = now) and
-- unarchived when it is reopened (any other status). Project_API lists the active tasks
-- (archived_at IS NULL) in the project detail and the archived ones in their own list;
-- the counters of a project keep counting both. BEFORE trigger: the row is written once.
CREATE OR REPLACE FUNCTION fn_set_task_archived_at()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'completed' THEN
        IF TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'completed' OR NEW.archived_at IS NULL THEN
            NEW.archived_at := COALESCE(
                CASE WHEN TG_OP = 'UPDATE' AND OLD.status = 'completed' THEN OLD.archived_at END,
                CURRENT_TIMESTAMP);
        END IF;
    ELSE
        NEW.archived_at := NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS tr_before_task_archive ON tasks;
CREATE TRIGGER tr_before_task_archive
    BEFORE INSERT OR UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION fn_set_task_archived_at();
