-- CREATE DATABASE mairie_360_database;

-- GRANT ALL PRIVILEGES ON DATABASE mairie_360_database TO postgres;

-- \c mairie_360_database


-- CREATE OR REPLACE FUNCTION update_updated_at_column()
-- RETURNS TRIGGER AS $$
-- BEGIN
--     NEW.updated_at = now();
--     RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- CREATE TABLE modules (
--     id SERIAL PRIMARY KEY,
--     name VARCHAR(64) UNIQUE NOT NULL,
--     description TEXT NOT NULL,
--     base_url TEXT NOT NULL
-- );

-- CREATE TABLE users (
--     id SERIAL PRIMARY KEY,
--     first_name VARCHAR(64) NOT NULL,
--     last_name VARCHAR(64) NOT NULL,
--     email VARCHAR(320) UNIQUE NOT NULL,
--     password CHAR(60) NOT NULL,
--     phone_number VARCHAR(15),
--     photo bytea,
--     status VARCHAR(16) NOT NULL CHECK (status IN ('active', 'inactive', 'pending', 'offline')) DEFAULT 'offline',
--     created_at TIMESTAMPTZ DEFAULT now(),
--     updated_at TIMESTAMPTZ DEFAULT now()
-- );

-- CREATE TRIGGER trg_users_updated_at
-- BEFORE UPDATE ON users
-- FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- CREATE TABLE sessions (
--     id SERIAL PRIMARY KEY,
--     user_id INT REFERENCES users(id) ON DELETE CASCADE,
--     token TEXT NOT NULL,
--     created_at TIMESTAMPTZ DEFAULT now(),
--     expires_at TIMESTAMPTZ NOT NULL
-- );

-- CREATE INDEX idx_sessions_user_id ON sessions(user_id);

-- CREATE TABLE roles (
--     id SERIAL PRIMARY KEY,
--     name VARCHAR(64) UNIQUE NOT NULL,
--     description TEXT
-- );

-- CREATE TABLE user_roles (
--     user_id INT REFERENCES users(id) ON DELETE CASCADE,
--     role_id INT REFERENCES roles(id) ON DELETE CASCADE,
--     PRIMARY KEY (user_id, role_id)
-- );

-- CREATE INDEX idx_user_roles_user_id ON user_roles(user_id);
-- CREATE INDEX idx_user_roles_role_id ON user_roles(role_id);

-- CREATE TABLE resources (
--     id SERIAL PRIMARY KEY,
--     module_id INT REFERENCES modules(id) ON DELETE CASCADE,
--     name VARCHAR(64) UNIQUE NOT NULL,
--     description TEXT,
--     updated_at TIMESTAMPTZ DEFAULT now()
-- );

-- CREATE TRIGGER trg_resources_updated_at
-- BEFORE UPDATE ON resources
-- FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- CREATE INDEX idx_resources_module_id ON resources(module_id);

-- CREATE TABLE permissions (
--     id SERIAL PRIMARY KEY,
--     resource_id INT REFERENCES resources(id) ON DELETE CASCADE,
--     action VARCHAR(16) NOT NULL CHECK (action IN ('create', 'read', 'update', 'delete', 'read_all', 'update_all', 'delete_all')),
--     description TEXT
-- );

-- CREATE INDEX idx_permissions_resource_id ON permissions(resource_id);

-- CREATE TABLE role_permissions (
--     role_id INT REFERENCES roles(id) ON DELETE CASCADE,
--     permission_id INT REFERENCES permissions(id) ON DELETE CASCADE,
--     PRIMARY KEY (role_id, permission_id)
-- );

-- CREATE INDEX idx_role_permissions_role_id ON role_permissions(role_id);
-- CREATE INDEX idx_role_permissions_permission_id ON role_permissions(permission_id);

-- DO
-- $$
-- BEGIN
--   IF NOT EXISTS (SELECT 1 FROM users) THEN
--     INSERT INTO users (first_name, last_name, email, password, status)
--     VALUES ('Admin', 'User', 'template.email@gmail.com', 'password_template', 'active');
--   END IF;
-- END;
-- $$;
