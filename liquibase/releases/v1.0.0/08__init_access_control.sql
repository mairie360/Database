-- 1. Table de Contrôle d'Accès (ACL)
CREATE TABLE access_control (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    group_id INT REFERENCES groups(id) ON DELETE CASCADE,
    resource_id INT REFERENCES resources(id) ON DELETE CASCADE,
    resource_instance_id INT NOT NULL,
    permission_id INT REFERENCES permissions(id) ON DELETE CASCADE,

    CONSTRAINT xor_user_group CHECK (
        (user_id IS NOT NULL AND group_id IS NULL) OR
        (user_id IS NULL AND group_id IS NOT NULL)
    ),

    CONSTRAINT uq_access_entry UNIQUE (user_id, group_id, resource_id, resource_instance_id, permission_id)
);

CREATE INDEX idx_acl_user_lookup ON access_control(user_id, resource_id, resource_instance_id);
CREATE INDEX idx_acl_group_lookup ON access_control(group_id, resource_id, resource_instance_id);

-- 2. Système de Logs d'Accès
DO $$ BEGIN
    CREATE TYPE access_result AS ENUM ('GRANTED', 'DENIED');
EXCEPTION WHEN duplicate_object THEN null; END $$;

CREATE TABLE access_logs (
    id SERIAL,
    user_id INT REFERENCES users(id),
    resource_name VARCHAR(64) NOT NULL,
    instance_id INT,
    action VARCHAR(32) NOT NULL,
    result access_result NOT NULL,
    reason TEXT,
    ip_address INET,
    timestamp TIMESTAMPTZ DEFAULT now(),
    -- La clé primaire DOIT inclure le timestamp pour le partitionnement
    PRIMARY KEY (id, timestamp)
) PARTITION BY RANGE (timestamp);

-- 3. Création d'une partition par défaut (Sinon les inserts échoueront)
CREATE TABLE access_logs_default PARTITION OF access_logs DEFAULT;

-- Index pour l'audit par les administrateurs
CREATE INDEX idx_access_logs_user ON access_logs(user_id, timestamp DESC);
CREATE INDEX idx_access_logs_resource ON access_logs(resource_name, instance_id);
