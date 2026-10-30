-- users_audit_log is append-only: no DELETE, and no UPDATE except the pseudonymization of
-- anonymize_user() (MAIR-289), which sets `mairie360.audit_pseudonymize` for its own transaction
-- and may only rewrite previous_data / new_data. The API roles have no privilege on the table
-- (MAIR-114), so only the owner could set that flag.
CREATE OR REPLACE FUNCTION fn_protect_audit_log() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND current_setting('mairie360.audit_pseudonymize', TRUE) = 'on'
       AND NEW.audit_id = OLD.audit_id
       AND NEW.user_id IS NOT DISTINCT FROM OLD.user_id
       AND NEW.action_type = OLD.action_type
       AND NEW.action_date IS NOT DISTINCT FROM OLD.action_date
       AND NEW.action_by IS NOT DISTINCT FROM OLD.action_by
       AND NEW.reason IS NOT DISTINCT FROM OLD.reason THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'users_audit_log is append-only';
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_immutable_audit ON users_audit_log;
CREATE TRIGGER tr_immutable_audit
    BEFORE UPDATE OR DELETE ON users_audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_protect_audit_log();
