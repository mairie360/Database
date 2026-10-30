-- Trigger: status of a task within the statuses of its project (MAIR-566).
--
-- tasks.status_id is a status of the task's own project; tasks.status keeps its category
-- (`todo`, `in_progress`, `completed`), the column the archiving trigger, the progress and
-- the pending task lists read. A writer may give either:
-- - status_id: it must belong to the task's project (23503 otherwise), the category follows;
-- - the category alone (a writer older than MAIR-566): the task takes the first status of
--   that category in the project, or keeps its status when it already is of that category.
--   `review` is read as `in_progress`.
-- BEFORE trigger, named to run before tr_before_task_archive (triggers fire by name), which
-- archives on the category it sets.
CREATE OR REPLACE FUNCTION fn_apply_task_status()
RETURNS TRIGGER AS $$
DECLARE
    v_category task_status;
BEGIN
    IF NEW.status_id IS NOT NULL AND (TG_OP = 'INSERT'
            OR NEW.status_id IS DISTINCT FROM OLD.status_id
            OR NEW.project_id IS DISTINCT FROM OLD.project_id) THEN
        SELECT category INTO v_category
        FROM project_task_statuses
        WHERE id = NEW.status_id AND project_id = NEW.project_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'status % is not a status of project %', NEW.status_id, NEW.project_id
                USING ERRCODE = 'foreign_key_violation';
        END IF;
        NEW.status := v_category;
        RETURN NEW;
    END IF;

    IF NEW.status = 'review' THEN
        NEW.status := 'in_progress';
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.status_id IS NOT NULL THEN
        SELECT category INTO v_category FROM project_task_statuses WHERE id = NEW.status_id;
        IF v_category = NEW.status THEN
            RETURN NEW;
        END IF;
    END IF;

    NEW.status_id := (
        SELECT id FROM project_task_statuses
        WHERE project_id = NEW.project_id AND category = NEW.status
        ORDER BY position, id
        LIMIT 1);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS tr_before_task_apply_status ON tasks;
CREATE TRIGGER tr_before_task_apply_status
    BEFORE INSERT OR UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION fn_apply_task_status();
