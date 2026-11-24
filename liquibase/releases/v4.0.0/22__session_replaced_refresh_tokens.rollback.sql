DROP FUNCTION IF EXISTS report_refresh_token_reuse(TEXT, INT, INET, TEXT);
DROP TRIGGER IF EXISTS tr_keep_replaced_refresh_token ON sessions;
DROP FUNCTION IF EXISTS fn_keep_replaced_refresh_token();
DROP TABLE IF EXISTS session_replaced_refresh_tokens;
-- REFRESH_REUSE stays in session_action: Postgres cannot drop an enum value.
