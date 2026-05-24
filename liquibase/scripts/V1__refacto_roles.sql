-- 1. Nettoyage des anciennes contraintes et index
ALTER TABLE user_roles DROP CONSTRAINT IF EXISTS fk_user_roles_user;
DROP INDEX IF EXISTS idx_user_roles_user;

-- 2. Suppression de la colonne devenue inutile
ALTER TABLE user_roles DROP COLUMN IF EXISTS user_is_archived;

-- 3. Recréation de la clé étrangère et de l'index corrigés
ALTER TABLE user_roles
    ADD CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id)
    REFERENCES users(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_user_roles_user ON user_roles(user_id);
