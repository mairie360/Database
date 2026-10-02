DROP FUNCTION IF EXISTS check_access(integer, character varying, character varying, integer);

-- SECURITY DEFINER: every API calls it (API_lib RightMiddleware) without
-- access to the RBAC/ACL tables nor to access_logs (MAIR-114). Only the API
-- roles may execute it (granted in security/api_grants.sql, MAIR-413), and
-- it only queries the tables named in `resources`, so it cannot be used to
-- probe arbitrary tables.
--
-- Returns 1 (granted), 0 (denied) or -1 (unknown resource or instance).
CREATE OR REPLACE FUNCTION check_access(
    p_user_id INT,
    p_resource_name VARCHAR,
    p_action VARCHAR,
    p_instance_id INT DEFAULT NULL
) RETURNS INT AS $$
DECLARE
    v_has_access BOOLEAN := FALSE;
    v_reason TEXT := 'NO_MATCH';
    v_instance_exists BOOLEAN := FALSE;
    v_user_archived BOOLEAN;
BEGIN
    -- Only resources declared in `resources` are checked: p_resource_name is
    -- used as a table name below.
    IF NOT EXISTS (SELECT 1 FROM resources WHERE name = p_resource_name) THEN
        RETURN -1;
    END IF;

    -- Unknown user: denied, and nothing to log (access_logs.user_id
    -- references users).
    SELECT is_archived INTO v_user_archived FROM users WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN 0;
    END IF;

    <<logic_flow>>
    LOOP
        -- 0. The requested instance must exist (404, not logged).
        IF p_instance_id IS NOT NULL THEN
            BEGIN
                EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE id = $1)', p_resource_name)
                USING p_instance_id INTO v_instance_exists;
            EXCEPTION WHEN undefined_table THEN
                -- A declared resource without a table of that name.
                RETURN -1;
            END;

            IF NOT v_instance_exists THEN
                RETURN -1;
            END IF;
        END IF;

        -- An archived account keeps its roles and ACLs (restore_user gives
        -- them back) but is denied everything.
        IF v_user_archived IS TRUE THEN
            v_reason := 'USER_ARCHIVED';
            EXIT logic_flow;
        END IF;

        -- 1. Global permission (<action>_all)
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

        -- 2. Ownership
        IF p_instance_id IS NOT NULL THEN
            DECLARE
                v_owner_found INT;
            BEGIN
                -- Try owner_id, then user_id; a table may have neither.
                BEGIN
                    EXECUTE format('SELECT owner_id FROM public.%I WHERE id = $1', p_resource_name)
                    USING p_instance_id INTO v_owner_found;
                    IF v_owner_found = p_user_id THEN v_has_access := TRUE; END IF;
                EXCEPTION WHEN undefined_column THEN NULL;
                END;

                IF NOT v_has_access THEN
                    BEGIN
                        EXECUTE format('SELECT user_id FROM public.%I WHERE id = $1', p_resource_name)
                        USING p_instance_id INTO v_owner_found;
                        IF v_owner_found = p_user_id THEN v_has_access := TRUE; END IF;
                    EXCEPTION WHEN undefined_column THEN NULL;
                    END;
                END IF;
            END;

            IF v_has_access THEN
                v_reason := 'OWNERSHIP';
                EXIT logic_flow;
            END IF;
        END IF;

        -- 3. Individual ACL
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

        -- 4. Group ACL
        IF p_instance_id IS NOT NULL THEN
            SELECT EXISTS (
                SELECT 1 FROM access_control ac
                JOIN group_members gu ON ac.group_id = gu.group_id
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

    -- Log every decision
    INSERT INTO access_logs (user_id, resource_name, instance_id, action, result, reason)
    VALUES (
        p_user_id,
        p_resource_name,
        p_instance_id,
        p_action,
        CASE WHEN v_has_access THEN 'GRANTED'::access_result ELSE 'DENIED'::access_result END,
        v_reason
    );

    -- 1 (granted) or 0 (denied)
    RETURN CASE WHEN v_has_access THEN 1 ELSE 0 END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION check_access(INT, VARCHAR, VARCHAR, INT) FROM PUBLIC;
