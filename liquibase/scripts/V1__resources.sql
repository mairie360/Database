-- 1. Table des ressources (Ta base)
CREATE TABLE resources (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64) UNIQUE NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Trigger pour la mise à jour auto (Assure-toi que la fonction existe déjà)
CREATE TRIGGER trg_resources_updated_at
BEFORE UPDATE ON resources
FOR EACH ROW EXECUTE FUNCTION update_modified_column();

-- 2. Insertion des données de référence
INSERT INTO resources (name, description) VALUES
    ('users', 'Gestion des comptes utilisateurs'),
    ('roles', 'Gestion des rôles et permissions'),
    ('sessions', 'Gestion des sessions actives'),
    ('session_setting', 'Configuration globale des sessions');

---
-- 3. Création des VUES "Securable"
-- Ces vues injectent dynamiquement l'ID de la ressource correspondante.
---

-- Vue pour les Utilisateurs
CREATE OR REPLACE VIEW v_securable_users AS
SELECT 
    u.*, 
    (SELECT id FROM resources WHERE name = 'users') as resource_id
FROM users u;

-- Vue pour les Rôles
CREATE OR REPLACE VIEW v_securable_roles AS
SELECT 
    r.*, 
    (SELECT id FROM resources WHERE name = 'roles') as resource_id
FROM roles r;

-- Vue pour les Sessions
CREATE OR REPLACE VIEW v_securable_sessions AS
SELECT 
    s.*, 
    (SELECT id FROM resources WHERE name = 'sessions') as resource_id
FROM sessions s;

-- Vue pour les Paramètres (cas particulier car table à ligne unique)
CREATE OR REPLACE VIEW v_securable_session_settings AS
SELECT 
    ss.*, 
    (SELECT id FROM resources WHERE name = 'session_setting') as resource_id
FROM session_settings ss;