CREATE TABLE permissions (
    id SERIAL PRIMARY KEY,
    resource_id INT REFERENCES resources(id) ON DELETE CASCADE,
    action VARCHAR(16) NOT NULL CHECK (action IN ('create', 'read', 'update', 'delete', 'read_all', 'update_all', 'delete_all')),
    description TEXT
);

CREATE INDEX idx_permissions_resource_id ON permissions(resource_id);
ALTER TABLE permissions ADD CONSTRAINT uq_resource_action UNIQUE (resource_id, action);

-- Permissions pour Users
INSERT INTO permissions (resource_id, action)
SELECT id, action FROM resources, 
(VALUES ('read_all'), ('read'), ('create'), ('update'), ('delete')) AS t(action)
WHERE name = 'users';

-- Permissions pour Roles
INSERT INTO permissions (resource_id, action)
SELECT id, action FROM resources, 
(VALUES ('read_all'), ('read'), ('create'), ('update_all'), ('update'), ('delete')) AS t(action)
WHERE name = 'roles';

-- Permissions pour Sessions
INSERT INTO permissions (resource_id, action)
SELECT id, action FROM resources, 
(VALUES ('read_all'), ('read'), ('create'), ('update_all'), ('update'), ('delete')) AS t(action)
WHERE name = 'sessions';

-- Permissions pour Session Settings
INSERT INTO permissions (resource_id, action)
SELECT id, action FROM resources, 
(VALUES ('read_all'), ('read'), ('update_all'), ('update')) AS t(action)
WHERE name = 'session_settings';
