-- 1. Table des rôles
CREATE TABLE IF NOT EXISTS roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    can_be_deleted BOOLEAN DEFAULT TRUE
);

-- Insertion des rôles de base
INSERT INTO roles (name, description, can_be_deleted)
VALUES
    ('Admin', 'Administrateur système', FALSE),
    ('Maire', 'Maire de la ville', FALSE),
    ('Responsable', 'Responsable de service', FALSE),
    ('User', 'Utilisateur standard', FALSE),
    ('Guest', 'Invité', FALSE)
ON CONFLICT (name) DO NOTHING;

-- 2. Table de jointure
CREATE TABLE IF NOT EXISTS user_roles (
    user_id INT NOT NULL,
    role_id INT NOT NULL,
    PRIMARY KEY (user_id, role_id),
    CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id)
        REFERENCES roles(id) ON DELETE CASCADE
);

-- 3. Indexation
CREATE INDEX IF NOT EXISTS idx_user_roles_user ON user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON user_roles(role_id);

-- 4. Attribution du rôle Admin à l'utilisateur ID 1 (si existant)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE id = 1) THEN
        INSERT INTO user_roles (user_id, role_id)
        VALUES (1, (SELECT id FROM roles WHERE name = 'Admin'))
        ON CONFLICT DO NOTHING;
    END IF;
END $$;
