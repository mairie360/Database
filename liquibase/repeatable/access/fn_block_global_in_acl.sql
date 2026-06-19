CREATE OR REPLACE FUNCTION fn_block_global_in_acl()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM permissions WHERE id = NEW.permission_id AND action LIKE '%\_all' ESCAPE '\') THEN
        RAISE EXCEPTION 'Une permission globale (_all) ne peut pas être utilisée dans la table access_control';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_check_acl_permission ON access_control;
CREATE TRIGGER tr_check_acl_permission
    BEFORE INSERT OR UPDATE ON access_control
    FOR EACH ROW EXECUTE FUNCTION fn_block_global_in_acl();
