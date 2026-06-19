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
