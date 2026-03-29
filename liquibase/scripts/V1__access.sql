CREATE TABLE access_control (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    resource_id INT REFERENCES resources(id) ON DELETE CASCADE,
    resource_instance_id INT NOT NULL,
    permission_id INT REFERENCES permissions(id) ON DELETE CASCADE,
    
    -- Empêche les doublons de permissions pour un même utilisateur sur un même objet
    CONSTRAINT uq_user_access UNIQUE (user_id, resource_id, resource_instance_id, permission_id)
);

-- Un seul index suffit
CREATE INDEX idx_acl_lookup ON access_control(user_id, resource_id, resource_instance_id);

CREATE OR REPLACE FUNCTION fn_block_global_in_acl()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM permissions WHERE id = NEW.permission_id AND action LIKE '%\_all' ESCAPE '\') THEN
        RAISE EXCEPTION 'Une permission globale (_all) ne peut pas être utilisée dans la table access_control';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_check_acl_permission
BEFORE INSERT OR UPDATE ON access_control
FOR EACH ROW EXECUTE FUNCTION fn_block_global_in_acl();

CREATE OR REPLACE FUNCTION check_access(
    p_user_id INT,
    p_resource_name VARCHAR,
    p_action VARCHAR,
    p_instance_id INT DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_has_access BOOLEAN := FALSE;
BEGIN
    -- 1. PRIORITÉ ABSOLUE : Le droit Global (_all)
    -- Vérifie si l'utilisateur possède un rôle avec la permission "action_all"
    SELECT EXISTS (
        SELECT 1 
        FROM rights r
        JOIN permissions p ON r.permission_id = p.id
        JOIN resources res ON p.resource_id = res.id
        JOIN user_roles ur ON ur.role_id = r.role_id
        WHERE ur.user_id = p_user_id
          AND res.name = p_resource_name
          AND p.action = (p_action || '_all')
    ) INTO v_has_access;

    IF v_has_access THEN RETURN TRUE; END IF;

    -- 2. NIVEAU INTERMÉDIAIRE : Propriété (Ownership / Identité)
    IF p_instance_id IS NOT NULL THEN
        BEGIN
            IF p_resource_name = 'users' THEN
                -- Cas spécial : l'utilisateur est l'instance elle-même (Identité)
                v_has_access := (p_instance_id = p_user_id);
            ELSE
                -- Cas général : vérifie si la table a une colonne user_id liée à l'utilisateur (Propriété)
                EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I WHERE id = $1 AND user_id = $2)', p_resource_name)
                USING p_instance_id, p_user_id 
                INTO v_has_access;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_has_access := FALSE; -- Sécurité si la table ou la colonne user_id n'existe pas
        END;
        
        IF v_has_access THEN RETURN TRUE; END IF;
    END IF;

    -- 3. DERNIER RECOURS : Accès spécifique (ACL / Partage)
    -- Vérifie si un droit explicite a été donné dans la table access_control
    IF p_instance_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
            FROM access_control ac
            JOIN permissions p ON ac.permission_id = p.id
            JOIN resources res ON ac.resource_id = res.id
            WHERE ac.user_id = p_user_id
              AND res.name = p_resource_name
              AND p.action = p_action
              AND ac.resource_instance_id = p_instance_id
        ) INTO v_has_access;
    END IF;

    RETURN COALESCE(v_has_access, FALSE);
END;
$$ LANGUAGE plpgsql;