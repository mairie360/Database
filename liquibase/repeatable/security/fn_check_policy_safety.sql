-- Fonction de sécurité
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

-- Attachement du Trigger
DROP TRIGGER IF EXISTS tr_safety_retention ON retention_policies;
CREATE TRIGGER tr_safety_retention
    BEFORE INSERT OR UPDATE ON retention_policies
    FOR EACH ROW EXECUTE FUNCTION check_policy_safety();
