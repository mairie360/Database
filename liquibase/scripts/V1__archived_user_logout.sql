CREATE OR REPLACE FUNCTION fn_logout_user_on_archive()
RETURNS TRIGGER AS $$
BEGIN
    -- Si on passe de non-archivé à archivé
    IF (OLD.is_archived = FALSE AND NEW.is_archived = TRUE) THEN
        DELETE FROM sessions WHERE user_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_05_logout_on_archive
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION fn_logout_user_on_archive();
    
    
ALTER TABLE connection_logs 
DROP CONSTRAINT connection_logs_user_id_user_is_archived_fkey;

ALTER TABLE connection_logs
ADD CONSTRAINT connection_logs_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;