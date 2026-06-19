CREATE OR REPLACE FUNCTION fn_audit_and_mutate_user()
RETURNS TRIGGER AS $$
DECLARE
    v_action user_audit_action;
    v_user_id INT;
BEGIN
    v_user_id := COALESCE(NULLIF(current_setting('myapp.current_user_id', true), ''), '0')::INT;

    IF (TG_OP = 'INSERT') THEN
        v_action := 'CREATE';
    ELSIF (TG_OP = 'UPDATE') THEN
        IF (OLD.is_archived = FALSE AND NEW.is_archived = TRUE) THEN v_action := 'ARCHIVE';
        ELSIF (OLD.is_archived = TRUE AND NEW.is_archived = FALSE) THEN v_action := 'RESTORE';
        ELSE v_action := 'UPDATE';
        END IF;
    END IF;

    INSERT INTO users_audit_log (user_id, action_type, action_by, previous_data, new_data)
    VALUES (
        COALESCE(NEW.id, OLD.id),
        v_action,
        v_user_id,
        CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END,
        to_jsonb(NEW)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_20_user_lifecycle_audit ON users;
CREATE TRIGGER tr_20_user_lifecycle_audit
    AFTER INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_audit_and_mutate_user();
