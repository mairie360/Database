-- Restores an archived account. An anonymized account (MAIR-289) has no identity left to restore:
-- refused.
CREATE OR REPLACE FUNCTION restore_user(target_id INT)
RETURNS VOID AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE id = target_id AND email = format('anonymized-%s@anonymized.invalid', id)) THEN
        RAISE EXCEPTION 'User % was anonymized and cannot be restored', target_id USING ERRCODE = 'restrict_violation';
    END IF;
    UPDATE users
    SET is_archived = FALSE,
        status = 'offline'
    WHERE id = target_id AND is_archived = TRUE;
END;
$$ LANGUAGE plpgsql;
