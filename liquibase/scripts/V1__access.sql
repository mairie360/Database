CREATE TABLE access_control (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    group_id INT REFERENCES groups(id) ON DELETE CASCADE, -- La nouveauté
    resource_id INT REFERENCES resources(id) ON DELETE CASCADE,
    resource_instance_id INT NOT NULL,
    permission_id INT REFERENCES permissions(id) ON DELETE CASCADE,
    
    -- Contrainte : Soit user_id est rempli, soit group_id, pas les deux.
    CONSTRAINT xor_user_group CHECK (
        (user_id IS NOT NULL AND group_id IS NULL) OR 
        (user_id IS NULL AND group_id IS NOT NULL)
    ),
    
    -- Mise à jour de l'unicité pour inclure le groupe
    CONSTRAINT uq_access_entry UNIQUE (user_id, group_id, resource_id, resource_instance_id, permission_id)
);

-- Un seul index suffit
CREATE INDEX idx_acl_user_lookup ON access_control(user_id, resource_id, resource_instance_id);
CREATE INDEX idx_acl_group_lookup ON access_control(group_id, resource_id, resource_instance_id);

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
    -- 1. NIVEAU GLOBAL : L'utilisateur a-t-il le droit "_all" ?
    -- (Ex: Un Admin qui a 'read_all' sur 'groups')
    SELECT EXISTS (
        SELECT 1 
        FROM user_roles ur
        JOIN rights r ON ur.role_id = r.role_id
        JOIN permissions p ON r.permission_id = p.id
        JOIN resources res ON p.resource_id = res.id
        WHERE ur.user_id = p_user_id
          AND res.name = p_resource_name
          AND p.action = (p_action || '_all')
    ) INTO v_has_access;

    IF v_has_access THEN RETURN TRUE; END IF;

    -- 2. NIVEAU PROPRIÉTÉ : L'utilisateur possède-t-il la ressource ?
    -- On vérifie dynamiquement si l'ID de l'instance appartient à l'user_id
    IF p_instance_id IS NOT NULL THEN
        BEGIN
            -- On vérifie les colonnes standard de propriété : user_id ou owner_id
            EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I WHERE id = $1 AND (user_id = $2 OR owner_id = $2))', p_resource_name)
            USING p_instance_id, p_user_id 
            INTO v_has_access;
        EXCEPTION WHEN OTHERS THEN 
            v_has_access := FALSE; 
        END;
        
        IF v_has_access THEN RETURN TRUE; END IF;
    END IF;

    -- 3. NIVEAU ACL INDIVIDUEL : Un droit spécifique a-t-il été donné à cet User ?
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
        
        IF v_has_access THEN RETURN TRUE; END IF;
    END IF;

    -- 4. NIVEAU ACL GROUPE : L'utilisateur appartient-il à un groupe ayant le droit ?
    IF p_instance_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
            FROM access_control ac
            JOIN group_users gu ON ac.group_id = gu.group_id
            JOIN permissions p ON ac.permission_id = p.id
            JOIN resources res ON ac.resource_id = res.id
            WHERE gu.user_id = p_user_id
              AND res.name = p_resource_name
              AND p.action = p_action
              AND ac.resource_instance_id = p_instance_id
        ) INTO v_has_access;
        
        IF v_has_access THEN RETURN TRUE; END IF;
    END IF;

    -- Si aucune étape n'a renvoyé TRUE, l'accès est refusé
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

CREATE TYPE access_result AS ENUM ('GRANTED', 'DENIED');

CREATE TABLE access_logs (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL, -- Qui a demandé ?
    resource_name VARCHAR(64) NOT NULL, -- Quelle table ? (ex: 'dossiers_urbanisme')
    instance_id INT, -- Quel ID spécifique ?
    action VARCHAR(32) NOT NULL, -- Quelle action ? (ex: 'read')
    result access_result NOT NULL, -- Accordé ou refusé ?
    reason TEXT, -- À quel niveau le droit a été trouvé (Global, Propriété, ACL, Groupe)
    ip_address INET, -- Optionnel, peut être récupéré via la session
    timestamp TIMESTAMPTZ DEFAULT now()
    PRIMARY KEY (id, timestamp) -- La clé de partition doit être dans la PK
) PARTITION BY RANGE (timestamp);

-- Index pour l'audit par les administrateurs de la mairie
CREATE INDEX idx_access_logs_user ON access_logs(user_id, timestamp DESC);
CREATE INDEX idx_access_logs_resource ON access_logs(resource_name, instance_id);

CREATE OR REPLACE FUNCTION check_access(
    p_user_id INT,
    p_resource_name VARCHAR,
    p_action VARCHAR,
    p_instance_id INT DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_has_access BOOLEAN := FALSE;
    v_reason TEXT := 'NO_MATCH';
BEGIN
    -- 1. NIVEAU GLOBAL
    SELECT EXISTS (
        SELECT 1 FROM user_roles ur
        JOIN rights r ON ur.role_id = r.role_id
        JOIN permissions p ON r.permission_id = p.id
        JOIN resources res ON p.resource_id = res.id
        WHERE ur.user_id = p_user_id
          AND res.name = p_resource_name
          AND p.action = (p_action || '_all')
    ) INTO v_has_access;

    IF v_has_access THEN v_reason := 'GLOBAL_PERMISSION'; GOTO log_and_return; END IF;

    -- 2. NIVEAU PROPRIÉTÉ
    IF p_instance_id IS NOT NULL THEN
        BEGIN
            EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I WHERE id = $1 AND (user_id = $2 OR owner_id = $2))', p_resource_name)
            USING p_instance_id, p_user_id INTO v_has_access;
        EXCEPTION WHEN OTHERS THEN v_has_access := FALSE; END;
        
        IF v_has_access THEN v_reason := 'OWNERSHIP'; GOTO log_and_return; END IF;
    END IF;

    -- 3. NIVEAU ACL INDIVIDUEL
    IF p_instance_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM access_control ac
            JOIN permissions p ON ac.permission_id = p.id
            JOIN resources res ON ac.resource_id = res.id
            WHERE ac.user_id = p_user_id
              AND res.name = p_resource_name
              AND p.action = p_action
              AND ac.resource_instance_id = p_instance_id
        ) INTO v_has_access;
        
        IF v_has_access THEN v_reason := 'INDIVIDUAL_ACL'; GOTO log_and_return; END IF;
    END IF;

    -- 4. NIVEAU ACL GROUPE
    IF p_instance_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM access_control ac
            JOIN group_users gu ON ac.group_id = gu.group_id
            JOIN permissions p ON ac.permission_id = p.id
            JOIN resources res ON ac.resource_id = res.id
            WHERE gu.user_id = p_user_id
              AND res.name = p_resource_name
              AND p.action = p_action
              AND ac.resource_instance_id = p_instance_id
        ) INTO v_has_access;
        
        IF v_has_access THEN v_reason := 'GROUP_ACL'; GOTO log_and_return; END IF;
    END IF;

<<log_and_return>>
    -- INSERTION DANS LE LOG D'ACCÈS
    INSERT INTO access_logs (user_id, resource_name, instance_id, action, result, reason)
    VALUES (
        p_user_id, 
        p_resource_name, 
        p_instance_id, 
        p_action, 
        CASE WHEN v_has_access THEN 'GRANTED'::access_result ELSE 'DENIED'::access_result END,
        v_reason
    );

    RETURN v_has_access;
END;
$$ LANGUAGE plpgsql;