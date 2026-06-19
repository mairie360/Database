---
-- STRUCTURE DES TABLES (SANS PARTITIONNEMENT POUR COMPATIBILITÉ FK)
---

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(64) NOT NULL,
    last_name VARCHAR(64) NOT NULL,
    email VARCHAR(320) NOT NULL,
    password VARCHAR(255) NOT NULL,
    phone_number VARCHAR(15),
    photo bytea,
    status VARCHAR(16) NOT NULL CHECK (status IN ('active', 'inactive', 'pending', 'offline', 'archived')) DEFAULT 'offline',
    is_archived BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT uq_users_identity UNIQUE (id)
);

-- Performances : Index filtré pour simuler la rapidité d'une partition
CREATE INDEX idx_users_not_archived ON users (id) WHERE is_archived = FALSE;

---
-- SYSTÈME D'AUDIT
---

DO $$ BEGIN
    CREATE TYPE user_audit_action AS ENUM ('CREATE', 'UPDATE', 'ARCHIVE', 'RESTORE');
EXCEPTION WHEN duplicate_object THEN null; END $$;

CREATE TABLE IF NOT EXISTS users_audit_log (
    audit_id SERIAL PRIMARY KEY,
    user_id INT,
    action_type user_audit_action NOT NULL,
    action_date TIMESTAMPTZ DEFAULT now(),
    action_by INT,
    previous_data JSONB,
    new_data JSONB,
    reason TEXT
);
