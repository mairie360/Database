CREATE OR REPLACE FUNCTION restore_user(target_id INT)
RETURNS VOID AS $$
BEGIN
    UPDATE users
    SET is_archived = FALSE,
        status = 'offline'
    WHERE id = target_id AND is_archived = TRUE;
END;
$$ LANGUAGE plpgsql;
