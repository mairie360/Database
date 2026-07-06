-- Trigger : Historique des tâches
CREATE OR REPLACE FUNCTION fn_log_task_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO task_history (task_id, old_status, new_status)
        VALUES (NEW.id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_after_task_status_update ON tasks;
CREATE TRIGGER tr_after_task_status_update AFTER UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION fn_log_task_status_change();
