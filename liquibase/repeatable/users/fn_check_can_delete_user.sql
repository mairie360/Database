CREATE OR REPLACE FUNCTION fn_check_can_delete_user()
RETURNS TRIGGER AS $$
DECLARE
    group_ids INT[];
    event_ids INT[];
    project_ids INT[];
    error_msg TEXT := '';
BEGIN
    -- 1. Récupération des IDs dans des tableaux
    SELECT array_agg(id) FROM groups WHERE owner_id = OLD.id INTO group_ids;
    SELECT array_agg(id) FROM events WHERE owner_id = OLD.id INTO event_ids;
    SELECT array_agg(id) FROM projects WHERE owner_id = OLD.id INTO project_ids;

    -- 2. Construction du message d'erreur si des dépendances existent
    IF group_ids IS NOT NULL THEN
        error_msg := error_msg || ' Groupes possédés: ' || array_to_string(group_ids, ', ');
    END IF;

    IF event_ids IS NOT NULL THEN
        error_msg := error_msg || ' | Events possédés: ' || array_to_string(event_ids, ', ');
    END IF;

    IF project_ids IS NOT NULL THEN
        error_msg := error_msg || ' | Projects possédés: ' || array_to_string(project_ids, ', ');
    END IF;

    -- 3. Si le message n'est pas vide, on bloque la suppression
    IF error_msg != '' THEN
        RAISE EXCEPTION 'Impossible de supprimer l''utilisateur % car il est encore propriétaire de ressources:%', OLD.id, error_msg
        USING ERRCODE = 'restrict_violation';
    END IF;

    -- Si tout est vide, on procède à l'archivage (ou la logique de ton choix)
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;
