CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_resources_updated_at
BEFORE UPDATE ON resources
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
