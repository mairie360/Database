-- 1. Drop the table if it already exists
DROP TABLE IF EXISTS group_users CASCADE;

-- 2. Table de Liaison (Membres)
CREATE TABLE group_users (
    group_id INT REFERENCES groups(id) ON DELETE CASCADE,
    user_id INT NOT NULL,
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (group_id, user_id),
    CONSTRAINT fk_group_users_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
);

-- 3. Fonction pour ajouter automatiquement l'owner comme membre
CREATE OR REPLACE FUNCTION add_owner_to_group_members()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO group_users (group_id, user_id)
    VALUES (NEW.id, NEW.owner_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Déclenchement du Trigger
-- Drop the trigger first to prevent "already exists" errors on rerun
DROP TRIGGER IF EXISTS trigger_add_owner_as_member ON groups;

CREATE TRIGGER trigger_add_owner_as_member
AFTER INSERT ON groups
FOR EACH ROW
EXECUTE FUNCTION add_owner_to_group_members();
