CREATE OR REPLACE FUNCTION fn_refresh_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_10_users_updated_at ON users;
CREATE TRIGGER tr_10_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_refresh_updated_at();
