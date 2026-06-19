CREATE OR REPLACE FUNCTION is_admin(
    p_user_id INT
)
RETURNS BOOLEAN
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM user_roles
        WHERE user_id = p_user_id
    );
END;
$$ LANGUAGE plpgsql;
