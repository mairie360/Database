-- 1. Création du type ENUM de stratégie
DO $$ BEGIN
    CREATE TYPE archive_strategy_type AS ENUM ('DELETE', 'COLD_STORAGE', 'PARTITION_DROP');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Table de configuration
CREATE TABLE IF NOT EXISTS retention_policies (
    table_name VARCHAR(64) PRIMARY KEY,
    retention_period INTERVAL NOT NULL,
    strategy archive_strategy_type NOT NULL,
    last_run TIMESTAMPTZ DEFAULT now()
);

-- 3. Insertion des politiques
INSERT INTO retention_policies (table_name, retention_period, strategy) VALUES
('sessions', '6 months', 'DELETE'),
('connection_logs', '1 year', 'COLD_STORAGE'),
('access_logs', '3 years', 'PARTITION_DROP'),
('users_audit_log', '10 years', 'COLD_STORAGE')
ON CONFLICT (table_name) DO UPDATE
SET retention_period = EXCLUDED.retention_period, strategy = EXCLUDED.strategy;
