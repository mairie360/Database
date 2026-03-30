-- 1. Nettoyage/SÉCURITÉ : On s'assure que les ressources ont les bons noms
UPDATE resources SET name = 'users' WHERE name IN ('users', 'user');
UPDATE resources SET name = 'roles' WHERE name IN ('roles', 'role');
UPDATE resources SET name = 'sessions' WHERE name IN ('sessions', 'session');
UPDATE resources SET name = 'session_setting' WHERE name IN ('session settings', 'session_settings');

-- 2. Insertion des permissions avec les noms CORRIGÉS
INSERT INTO permissions (resource_id, action)
SELECT id, action FROM resources, 
(VALUES ('read_all'), ('read'), ('create'), ('update'), ('delete')) AS t(action)
WHERE name = 'users'
ON CONFLICT DO NOTHING;

INSERT INTO permissions (resource_id, action)
SELECT id, action FROM resources, 
(VALUES ('read_all'), ('read'), ('create'), ('update_all'), ('update'), ('delete')) AS t(action)
WHERE name = 'roles'
ON CONFLICT DO NOTHING;

INSERT INTO permissions (resource_id, action)
SELECT id, action FROM resources, 
(VALUES ('read_all'), ('read'), ('create'), ('update_all'), ('update'), ('delete')) AS t(action)
WHERE name = 'sessions'
ON CONFLICT DO NOTHING;

INSERT INTO permissions (resource_id, action)
SELECT id, action FROM resources, 
(VALUES ('read_all'), ('read'), ('update_all'), ('update')) AS t(action)
WHERE name = 'session_setting'
ON CONFLICT DO NOTHING;

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
    (SELECT id FROM resources WHERE name = 'session_settings') as resource_id
FROM session_settings ss;