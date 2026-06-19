CREATE OR REPLACE FUNCTION is_session_valid(p_token_hash TEXT, p_device_info TEXT)
RETURNS TABLE(valid BOOLEAN, user_id INT) AS $$
BEGIN
    RETURN QUERY
    SELECT TRUE, s.user_id
    FROM v_sessions s
    WHERE s.token_hash = p_token_hash
      AND s.is_active = TRUE
      AND (s.device_info = p_device_info OR s.device_info IS NULL)
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;
