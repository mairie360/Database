CREATE OR REPLACE FUNCTION fn_soft_delete_user_from_view()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE users
    SET is_archived = TRUE,
        status = 'archived'
    WHERE id = OLD.id AND is_archived = FALSE;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_view_soft_delete ON v_users_active;
CREATE TRIGGER tr_view_soft_delete
    INSTEAD OF DELETE ON v_users_active
    FOR EACH ROW EXECUTE FUNCTION fn_soft_delete_user_from_view();
