-- Fonction corrigée aux standards PostgreSQL
CREATE OR REPLACE FUNCTION fn_set_group_accesses() RETURNS TRIGGER AS $$
BEGIN
    -- Insertion dans l'ACL en utilisant l'objet NEW pour récupérer les valeurs de la ligne insérée
    INSERT INTO access_control (group_id, resource_id, resource_instance_id, permission_id)
    SELECT NEW.owner_group_id, res.id, NEW.id, p.id
    FROM resources res, permissions p
    WHERE res.name = 'events'
      AND p.action IN ('read', 'update', 'delete');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attachement du trigger (en AFTER INSERT pour garantir que l'ID de l'événement existe)
DROP TRIGGER IF EXISTS trigger_set_group_accesses ON events;
CREATE TRIGGER trigger_set_group_accesses
    AFTER INSERT ON events
    FOR EACH ROW
    WHEN (NEW.owner_group_id IS NOT NULL) -- Remplace le WHERE de ton script original
    EXECUTE FUNCTION fn_set_group_accesses();
