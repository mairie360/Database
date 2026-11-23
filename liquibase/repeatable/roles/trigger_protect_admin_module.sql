-- MAIR-916: the Admin role always opens the Administration module (its agents would otherwise lose
-- the console that gives it back). Removing that row, or turning it into another module, is refused
-- (23514); every other module of every role stays free.
CREATE OR REPLACE FUNCTION fn_protect_admin_module()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.module = 'admin'
       AND (TG_OP = 'DELETE' OR NEW.module <> 'admin' OR NEW.role_id <> OLD.role_id)
       AND EXISTS (SELECT 1 FROM roles WHERE id = OLD.role_id AND name = 'Admin') THEN
        RAISE EXCEPTION 'The Admin role always opens the Administration module'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_role_modules_protect_admin ON role_modules;
CREATE TRIGGER tr_role_modules_protect_admin
    BEFORE UPDATE OR DELETE ON role_modules
    FOR EACH ROW
    EXECUTE FUNCTION fn_protect_admin_module();
