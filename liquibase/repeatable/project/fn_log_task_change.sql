-- Trigger : historique des tâches (MAIR-393).
--
-- task_history is written here only, never by a client: one `task_created`
-- row on INSERT, one `status_changed` row per status change, and one
-- `task_updated` row listing every other changed field as
-- {"<field>": {"from": …, "to": …}}. Rows are signed with tasks.updated_by,
-- which Project_API sets on every write (NULL = system write).
--
-- SECURITY DEFINER: project_api only reads task_history (api_grants.sql), so
-- the history cannot be written, edited or deleted outside this trigger.
DROP TRIGGER IF EXISTS tr_after_task_status_update ON tasks;
DROP FUNCTION IF EXISTS fn_log_task_status_change();

CREATE OR REPLACE FUNCTION fn_log_task_change()
RETURNS TRIGGER AS $$
DECLARE
    v_changes JSONB := '{}'::JSONB;
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO task_history (task_id, changed_by, action, new_status)
        VALUES (NEW.id, NEW.updated_by, 'task_created', NEW.status);
        RETURN NEW;
    END IF;

    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO task_history (task_id, changed_by, action, old_status, new_status, changes)
        VALUES (NEW.id, NEW.updated_by, 'status_changed', OLD.status, NEW.status,
                jsonb_build_object('status', jsonb_build_object('from', OLD.status, 'to', NEW.status)));
    END IF;

    IF OLD.title IS DISTINCT FROM NEW.title THEN
        v_changes := v_changes || jsonb_build_object('title', jsonb_build_object('from', OLD.title, 'to', NEW.title));
    END IF;
    IF OLD.description IS DISTINCT FROM NEW.description THEN
        v_changes := v_changes || jsonb_build_object('description', jsonb_build_object('from', OLD.description, 'to', NEW.description));
    END IF;
    IF OLD.priority IS DISTINCT FROM NEW.priority THEN
        v_changes := v_changes || jsonb_build_object('priority', jsonb_build_object('from', OLD.priority, 'to', NEW.priority));
    END IF;
    IF OLD.due_date IS DISTINCT FROM NEW.due_date THEN
        v_changes := v_changes || jsonb_build_object('due_date', jsonb_build_object(
            'from', to_char(OLD.due_date, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
            'to', to_char(NEW.due_date, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    END IF;
    IF OLD.assigned_to IS DISTINCT FROM NEW.assigned_to THEN
        v_changes := v_changes || jsonb_build_object('assigned_to', jsonb_build_object('from', OLD.assigned_to, 'to', NEW.assigned_to));
    END IF;
    IF OLD.custom_fields->'fields' IS DISTINCT FROM NEW.custom_fields->'fields' THEN
        v_changes := v_changes || jsonb_build_object('fields', jsonb_build_object(
            'from', OLD.custom_fields->'fields', 'to', NEW.custom_fields->'fields'));
    END IF;

    IF v_changes <> '{}'::JSONB THEN
        INSERT INTO task_history (task_id, changed_by, action, changes)
        VALUES (NEW.id, NEW.updated_by, 'task_updated', v_changes);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS tr_after_task_change ON tasks;
CREATE TRIGGER tr_after_task_change
    AFTER INSERT OR UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION fn_log_task_change();
