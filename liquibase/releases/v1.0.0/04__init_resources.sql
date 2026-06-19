-- 1. Table des ressources
CREATE TABLE resources (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64) UNIQUE NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Insertion des données de référence
INSERT INTO resources (name, description) VALUES
    ('users', 'Gestion des comptes utilisateurs'),
    ('roles', 'Gestion des rôles et permissions'),
    ('sessions', 'Gestion des sessions actives'),
    ('session_setting', 'Configuration globale des sessions')
ON CONFLICT (name) DO NOTHING;
