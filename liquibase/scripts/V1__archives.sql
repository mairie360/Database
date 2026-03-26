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

-- 3. Insertion des politiques pour la mairie
INSERT INTO retention_policies (table_name, retention_period, strategy) VALUES 
('sessions', '6 months', 'DELETE'),
('connection_logs', '1 year', 'COLD_STORAGE'),
('access_logs', '3 years', 'PARTITION_DROP'),
('users_audit_log', '10 years', 'COLD_STORAGE')
ON CONFLICT (table_name) DO UPDATE 
SET retention_period = EXCLUDED.retention_period, strategy = EXCLUDED.strategy;

-- 4. Fonction de sécurité (optionnel mais recommandé)
-- Empêche de configurer PARTITION_DROP sur une table critique comme 'users'
CREATE OR REPLACE FUNCTION check_policy_safety()
RETURNS TRIGGER AS $$
DECLARE
    -- Liste des tables critiques qui ne doivent JAMAIS être supprimées par partition
    critical_tables TEXT[] := ARRAY[
        'users', 
        'access_control', 
        'groups', 
        'permissions', 
        'resources', 
        'rights', 
        'roles', 
        'group_users', 
        'user_roles'
    ];
BEGIN
    -- 1. Sécurité sur PARTITION_DROP
    -- On interdit cette stratégie sur les tables qui ne sont pas techniquement partitionnées
    IF NEW.strategy = 'PARTITION_DROP' AND NEW.table_name = ANY(critical_tables) THEN
        RAISE EXCEPTION 'Sécurité : La table % ne peut pas utiliser PARTITION_DROP car elle n''est pas partitionnée ou est trop critique.', NEW.table_name;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_safety_retention
BEFORE INSERT OR UPDATE ON retention_policies
FOR EACH ROW EXECUTE FUNCTION check_policy_safety();