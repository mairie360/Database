CREATE TABLE resources (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64) UNIQUE NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TRIGGER trg_resources_updated_at
BEFORE UPDATE ON resources
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

INSERT INTO resources (name, description) VALUES
    ('user', 'user');

INSERT INTO resources (name, description) VALUES
    ('role', 'role');

INSERT INTO resources (name, description) VALUES
    ('session', 'Connection session');

INSERT INTO resources (name, description) VALUES
    ('session settings', 'Session settings');
