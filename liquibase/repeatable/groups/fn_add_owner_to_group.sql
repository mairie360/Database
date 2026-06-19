CREATE OR REPLACE FUNCTION add_owner_to_group_members()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO group_users (group_id, user_id)
    VALUES (NEW.id, NEW.owner_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_add_owner_as_member ON groups;
CREATE TRIGGER trigger_add_owner_as_member
    AFTER INSERT ON groups
    FOR EACH ROW
    EXECUTE FUNCTION add_owner_to_group_members();
