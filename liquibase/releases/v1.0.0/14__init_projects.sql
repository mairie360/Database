-- 1. Types ENUM (Sécurisés)
DO $$ BEGIN
    CREATE TYPE project_status AS ENUM ('active', 'suspended', 'completed');
    CREATE TYPE task_status AS ENUM ('todo', 'in_progress', 'completed');
    CREATE TYPE task_priority AS ENUM ('low', 'medium', 'high');
    CREATE TYPE field_type AS ENUM ('date', 'checkbox', 'select');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- 2. Tables
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status project_status DEFAULT 'active' NOT NULL,
    owner_id INT REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE project_members (
    project_id INT REFERENCES projects(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (project_id, user_id)
);

CREATE TABLE tasks (
    id SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    status task_status DEFAULT 'todo' NOT NULL,
    priority task_priority DEFAULT 'medium' NOT NULL,
    due_date TIMESTAMP,
    assigned_to INT REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE task_history (
    id SERIAL PRIMARY KEY,
    task_id INT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    changed_by INT REFERENCES users(id) ON DELETE SET NULL,
    old_status task_status,
    new_status task_status,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE project_field_templates (
    id SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    label VARCHAR(100) NOT NULL,
    type_champ field_type NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE field_select_options (
    id SERIAL PRIMARY KEY,
    template_id INT NOT NULL REFERENCES project_field_templates(id) ON DELETE CASCADE,
    option_value VARCHAR(100) NOT NULL,
    sort_order INT DEFAULT 1
);

CREATE TABLE task_custom_values (
    id SERIAL PRIMARY KEY,
    task_id INT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    template_id INT NOT NULL REFERENCES project_field_templates(id) ON DELETE CASCADE,
    value_date TIMESTAMP DEFAULT NULL,
    value_text TEXT DEFAULT NULL,
    CONSTRAINT u_task_field UNIQUE (task_id, template_id)
);

CREATE TABLE task_custom_options (
    custom_value_id INT NOT NULL REFERENCES task_custom_values(id) ON DELETE CASCADE,
    option_id INT NOT NULL REFERENCES field_select_options(id) ON DELETE CASCADE,
    PRIMARY KEY (custom_value_id, option_id)
);

-- Droits Admin
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Admin' AND res.name = 'projects'
AND p.action IN ('read_all', 'create', 'update_all', 'delete_all')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Maire
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Maire' AND res.name = 'projects'
AND p.action IN ('read_all', 'create', 'update', 'delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Responsable
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Responsable' AND res.name = 'projects'
AND p.action IN ('read', 'create', 'update', 'delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits User
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'User' AND res.name = 'projects'
AND p.action IN ('read')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Guest
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Guest' AND res.name = 'projects'
AND p.action IN ('read')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Admin
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Admin' AND res.name = 'tasks'
AND p.action IN ('read_all', 'create', 'update_all', 'delete_all')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Maire
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Maire' AND res.name = 'tasks'
AND p.action IN ('read_all', 'create', 'update', 'delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Responsable
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Responsable' AND res.name = 'tasks'
AND p.action IN ('read', 'create', 'update', 'delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits User
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'User' AND res.name = 'tasks'
AND p.action IN ('read', 'create', 'update', 'delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Guest
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Guest' AND res.name = 'tasks'
AND p.action IN ('read')
ON CONFLICT (role_id, permission_id) DO NOTHING;
