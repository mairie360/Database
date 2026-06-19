CREATE OR REPLACE VIEW v_users_active AS
SELECT * FROM users WHERE is_archived = FALSE;

CREATE OR REPLACE VIEW v_users_archived AS
SELECT * FROM users WHERE is_archived = TRUE;
