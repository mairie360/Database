DROP TRIGGER IF EXISTS trg_user_identities_updated_at ON user_identities;
CREATE TRIGGER trg_user_identities_updated_at
    BEFORE UPDATE ON user_identities
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
