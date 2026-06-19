-- 1. Enums (Sécurisés pour réexécution)
DO $$ BEGIN
    CREATE TYPE progress_status AS ENUM ('not_started', 'in_progress', 'completed');
    CREATE TYPE attachment_type AS ENUM ('video', 'pdf', 'document');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- 2. Tables de structure
CREATE TABLE courses (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE course_modules (
    id SERIAL PRIMARY KEY,
    course_id INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content TEXT,
    sort_order INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE course_attachments (
    id SERIAL PRIMARY KEY,
    module_id INT NOT NULL REFERENCES course_modules(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    file_type attachment_type NOT NULL,
    file_url TEXT NOT NULL,
    file_size_bytes BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_courses (
    user_id INT NOT NULL REFERENCES usev_users_activers(id) ON DELETE CASCADE,
    course_id INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    status progress_status DEFAULT 'not_started' NOT NULL,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    PRIMARY KEY (user_id, course_id)
);

CREATE TABLE user_modules (
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    module_id INT NOT NULL REFERENCES course_modules(id) ON DELETE CASCADE,
    is_completed BOOLEAN DEFAULT FALSE NOT NULL,
    completed_at TIMESTAMP,
    PRIMARY KEY (user_id, module_id)
);

-- 3. Index de performance
CREATE INDEX idx_user_courses_status ON user_courses(user_id, status);
CREATE INDEX idx_user_modules_lookup ON user_modules(user_id, is_completed);

-- Droits Admin
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Admin' AND res.name = 'user_courses'
AND p.action IN ('read_all', 'delete_all')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Maire
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Maire' AND res.name = 'user_courses'
AND p.action IN ('read', 'update')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Responsable
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Responsable' AND res.name = 'user_courses'
AND p.action IN ('read', 'update')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits User
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'User' AND res.name = 'user_courses'
AND p.action IN ('read', 'update')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Admin
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Admin' AND res.name = 'user_modules'
AND p.action IN ('read_all', 'delete_all')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Maire
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Maire' AND res.name = 'user_modules'
AND p.action IN ('read', 'update')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Responsable
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Responsable' AND res.name = 'user_modules'
AND p.action IN ('read', 'update')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits User
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'User' AND res.name = 'user_modules'
AND p.action IN ('read', 'update')
ON CONFLICT (role_id, permission_id) DO NOTHING;
