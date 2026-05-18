DROP FUNCTION IF EXISTS check_access(integer, character varying, character varying, integer);

CREATE OR REPLACE FUNCTION check_access(
    p_user_id INT,
    p_resource_name VARCHAR,
    p_action VARCHAR,
    p_instance_id INT DEFAULT NULL
) RETURNS INT AS $$ -- Changement ici: RETURNS INT
DECLARE
    v_has_access BOOLEAN := FALSE;
    v_reason TEXT := 'NO_MATCH';
    v_instance_exists BOOLEAN := FALSE;
BEGIN
    <<logic_flow>>
    LOOP
        -- ----------------------------------------------------
        -- ÉTAPE 0 : VÉRIFICATION DE L'EXISTENCE (Si instance demandée)
        -- ----------------------------------------------------
        IF p_instance_id IS NOT NULL THEN
            BEGIN
                EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE id = $1)', p_resource_name)
                USING p_instance_id INTO v_instance_exists;
            EXCEPTION WHEN OTHERS THEN
                -- Si la table n'existe pas (faute de frappe dans le code Rust)
                v_reason := 'RESOURCE_TABLE_NOT_FOUND';
                RETURN -1;
            END;

            IF NOT v_instance_exists THEN
                v_reason := 'INSTANCE_NOT_FOUND';
                RETURN -1; -- Sortie immédiate en 404 (Le log d'accès n'est pas requis pour une 404)
            END IF;
        END IF;

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

        IF v_has_access THEN
            v_reason := 'GLOBAL_PERMISSION';
            EXIT logic_flow;
        END IF;

        -- 2. NIVEAU PROPRIÉTÉ
        IF p_instance_id IS NOT NULL THEN
            DECLARE
                v_owner_found INT;
            BEGIN
                -- Tentative 1 : owner_id
                BEGIN
                    EXECUTE format('SELECT owner_id FROM public.%I WHERE id = $1', p_resource_name)
                    USING p_instance_id INTO v_owner_found;
                    IF v_owner_found = p_user_id THEN v_has_access := TRUE; END IF;
                EXCEPTION WHEN OTHERS THEN NULL;
                END;

                -- Tentative 2 : user_id
                IF NOT v_has_access THEN
                    BEGIN
                        EXECUTE format('SELECT user_id FROM public.%I WHERE id = $1', p_resource_name)
                        USING p_instance_id INTO v_owner_found;
                        IF v_owner_found = p_user_id THEN v_has_access := TRUE; END IF;
                    EXCEPTION WHEN OTHERS THEN NULL;
                    END;
                END IF;
            END;

            IF v_has_access THEN
                v_reason := 'OWNERSHIP';
                EXIT logic_flow;
            END IF;
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

            IF v_has_access THEN
                v_reason := 'INDIVIDUAL_ACL';
                EXIT logic_flow;
            END IF;
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

            IF v_has_access THEN
                v_reason := 'GROUP_ACL';
                EXIT logic_flow;
            END IF;
        END IF;

        EXIT;
    END LOOP logic_flow;

    -- LOGIQUE DE LOG
    INSERT INTO access_logs (user_id, resource_name, instance_id, action, result, reason)
    VALUES (
        p_user_id,
        p_resource_name,
        p_instance_id,
        p_action,
        CASE WHEN v_has_access THEN 'GRANTED'::access_result ELSE 'DENIED'::access_result END,
        v_reason
    );

    -- Retourne 1 (Autorisé) ou 0 (Interdit)
    RETURN CASE WHEN v_has_access THEN 1 ELSE 0 END;
END;
$$ LANGUAGE plpgsql;
