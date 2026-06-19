CREATE OR REPLACE FUNCTION fn_protect_audit_log() RETURNS TRIGGER AS $$
BEGIN RAISE EXCEPTION 'Interdit : Modification de l’audit impossible.'; END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_immutable_audit ON users_audit_log;
CREATE TRIGGER tr_immutable_audit
    BEFORE UPDATE OR DELETE ON users_audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_protect_audit_log();
