-- Services of the mairie (MAIR-923 F06): the administration keeps the list, each agent belongs to at
-- most one. Expand only: a new table and a nullable column; deleting a service leaves its agents
-- without one.
CREATE TABLE services (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_services_name CHECK (length(btrim(name)) BETWEEN 1 AND 64)
);
CREATE UNIQUE INDEX uq_services_name_lower ON services (lower(name));

ALTER TABLE users ADD COLUMN service_id INT REFERENCES services(id) ON DELETE SET NULL;
CREATE INDEX idx_users_service_id ON users (service_id);
