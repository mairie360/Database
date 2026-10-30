-- Triggers: statuses of a project or a template stay usable (MAIR-566).
--
-- fn_check_status_categories: a project (or a template) keeps at least one status in each
-- category (`todo`, `in_progress`, `completed`), so a task can always be created, started
-- and completed, and a writer giving the category alone always finds a status. Constraint
-- triggers deferred to the commit: a transaction may replace a status by another one. A
-- deleted project or template (cascade) is not checked. 23514 when a category is left empty.
--
-- fn_sync_status_category: changing the category of a project status moves its tasks to
-- that category (tasks.status), so their archiving and progress follow. System write
-- (updated_by NULL) in the task history.
CREATE OR REPLACE FUNCTION fn_check_status_categories()
RETURNS TRIGGER AS $$
DECLARE
    v_owner INT;
    v_missing TEXT;
BEGIN
    IF TG_TABLE_NAME = 'project_task_statuses' THEN
        v_owner := CASE WHEN TG_OP = 'INSERT' THEN NEW.project_id ELSE OLD.project_id END;
        IF NOT EXISTS (SELECT 1 FROM projects WHERE id = v_owner) THEN
            RETURN NULL;
        END IF;
        SELECT string_agg(c::TEXT, ', ') INTO v_missing
        FROM unnest(ARRAY['todo', 'in_progress', 'completed']::task_status[]) AS c
        WHERE NOT EXISTS (
            SELECT 1 FROM project_task_statuses WHERE project_id = v_owner AND category = c);
    ELSE
        v_owner := CASE WHEN TG_OP = 'INSERT' THEN NEW.template_id ELSE OLD.template_id END;
        IF NOT EXISTS (SELECT 1 FROM project_templates WHERE id = v_owner) THEN
            RETURN NULL;
        END IF;
        SELECT string_agg(c::TEXT, ', ') INTO v_missing
        FROM unnest(ARRAY['todo', 'in_progress', 'completed']::task_status[]) AS c
        WHERE NOT EXISTS (
            SELECT 1 FROM project_template_statuses WHERE template_id = v_owner AND category = c);
    END IF;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '% % must keep a status in each category, none left in: %',
            CASE WHEN TG_TABLE_NAME = 'project_task_statuses' THEN 'project' ELSE 'template' END,
            v_owner, v_missing
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS tr_check_project_status_categories ON project_task_statuses;
CREATE CONSTRAINT TRIGGER tr_check_project_status_categories
    AFTER INSERT OR UPDATE OR DELETE ON project_task_statuses
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_check_status_categories();

DROP TRIGGER IF EXISTS tr_check_template_status_categories ON project_template_statuses;
CREATE CONSTRAINT TRIGGER tr_check_template_status_categories
    AFTER INSERT OR UPDATE OR DELETE ON project_template_statuses
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_check_status_categories();

CREATE OR REPLACE FUNCTION fn_sync_status_category()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE tasks SET status = NEW.category, updated_by = NULL
    WHERE status_id = NEW.id AND status IS DISTINCT FROM NEW.category;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS tr_after_project_status_category ON project_task_statuses;
CREATE TRIGGER tr_after_project_status_category
    AFTER UPDATE OF category ON project_task_statuses
    FOR EACH ROW WHEN (OLD.category IS DISTINCT FROM NEW.category)
    EXECUTE FUNCTION fn_sync_status_category();
