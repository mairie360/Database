-- Database side of the per-instance compliance service (MAIR-498, Compliance_API).
-- Everything here returns counts and locations, never a value of a person: the service journals
-- what it finds in compliance_journal (releases/v3.0.1/07) without the data.

-- compliance_journal is append-only: it is the proof of erasure kept for the mairie.
CREATE OR REPLACE FUNCTION fn_protect_compliance_journal() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'compliance_journal is append-only' USING ERRCODE = 'P0001';
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS tr_immutable_compliance_journal ON compliance_journal;
CREATE TRIGGER tr_immutable_compliance_journal
    BEFORE UPDATE OR DELETE ON compliance_journal
    FOR EACH ROW EXECUTE FUNCTION fn_protect_compliance_journal();

-- The deterministic scan of the database, guided by the retention policies and the erasure of
-- MAIR-289. One row per finding: kind, location (table or table.column), rows, detail (a period or
-- a rule, never a value). The free text of the messages is out of scope by decision.
--   retention_overdue   rows older than the period of their retention_policies row;
--   archived_overdue    accounts archived for longer than the `users` policy, not anonymized yet;
--   erased_user_data    rows still attached to an anonymized account in a table its erasure empties,
--                       or a personal column of users left filled on an anonymized account.
DROP FUNCTION IF EXISTS fn_compliance_scan();
CREATE FUNCTION fn_compliance_scan()
RETURNS TABLE (kind TEXT, location TEXT, rows BIGINT, detail TEXT) AS $$
DECLARE
    v_policy RECORD;
    v_column TEXT;
    v_count BIGINT;
    v_table TEXT;
BEGIN
    FOR v_policy IN SELECT p.table_name, p.retention_period FROM retention_policies p ORDER BY p.table_name LOOP
        v_column := CASE v_policy.table_name
            WHEN 'sessions' THEN 'created_at'
            WHEN 'connection_logs' THEN 'timestamp'
            WHEN 'access_logs' THEN 'timestamp'
            WHEN 'users_audit_log' THEN 'action_date'
            ELSE NULL END;
        IF v_policy.table_name = 'users' THEN
            SELECT count(*) INTO v_count
            FROM users u
            WHERE u.is_archived IS TRUE AND u.id <> 1 AND NOT is_user_anonymized(u.id)
              AND coalesce((SELECT max(a.action_date) FROM users_audit_log a
                            WHERE a.user_id = u.id AND a.action_type = 'ARCHIVE'), u.updated_at)
                  < now() - v_policy.retention_period;
            IF v_count > 0 THEN
                kind := 'archived_overdue'; location := 'users'; rows := v_count;
                detail := 'archived longer than ' || v_policy.retention_period::TEXT;
                RETURN NEXT;
            END IF;
        ELSIF v_column IS NOT NULL AND to_regclass('public.' || v_policy.table_name) IS NOT NULL THEN
            EXECUTE format('SELECT count(*) FROM public.%I WHERE %I < now() - $1', v_policy.table_name, v_column)
                INTO v_count USING v_policy.retention_period;
            IF v_count > 0 THEN
                kind := 'retention_overdue'; location := v_policy.table_name; rows := v_count;
                detail := 'older than ' || v_policy.retention_period::TEXT;
                RETURN NEXT;
            END IF;
        END IF;
    END LOOP;

    -- Tables anonymize_user() empties for the erased account (MAIR-289).
    FOREACH v_table IN ARRAY ARRAY['access_control', 'conversation_members', 'conversation_read_cursors',
        'course_ratings', 'event_members', 'group_members', 'message_mentions', 'project_members',
        'recurrence_members', 'sessions', 'task_assignees', 'unread_counters', 'user_calendar_params',
        'user_content_progress', 'user_identities', 'user_modules', 'user_notification_settings',
        'user_preferences', 'user_roles']
    LOOP
        EXECUTE format(
            'SELECT count(*) FROM public.%I t JOIN users u ON u.id = t.user_id
              WHERE u.email = format(''anonymized-%%s@anonymized.invalid'', u.id)', v_table)
            INTO v_count;
        IF v_count > 0 THEN
            kind := 'erased_user_data'; location := v_table || '.user_id'; rows := v_count;
            detail := 'rows still attached to an anonymized account';
            RETURN NEXT;
        END IF;
    END LOOP;
    SELECT count(*) INTO v_count
    FROM users u
    WHERE u.email = format('anonymized-%s@anonymized.invalid', u.id)
      AND (u.password IS NOT NULL OR u.phone_number IS NOT NULL OR u.photo IS NOT NULL OR u.biography IS NOT NULL
           OR u.first_name <> 'Anonymized' OR u.last_name <> 'User');
    IF v_count > 0 THEN
        kind := 'erased_user_data'; location := 'users'; rows := v_count;
        detail := 'personal columns left filled on an anonymized account';
        RETURN NEXT;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

-- What the compliance service needs to propagate the erasure of a user outside the database,
-- read BEFORE anonymize_user() clears it: the e-mail (Resend contact, Keycloak lookup) and the
-- Keycloak subject. NULL for an unknown or already anonymized account.
DROP FUNCTION IF EXISTS fn_erasure_targets(INT);
CREATE FUNCTION fn_erasure_targets(p_user_id INT)
RETURNS JSONB AS $$
    SELECT jsonb_build_object(
        'user_id', u.id,
        'email', u.email,
        'keycloak_subject', (SELECT i.subject FROM user_identities i WHERE i.user_id = u.id AND i.provider = 'keycloak' LIMIT 1)
    )
    FROM users u
    WHERE u.id = p_user_id AND u.email <> format('anonymized-%s@anonymized.invalid', u.id);
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION fn_compliance_scan() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_erasure_targets(INT) FROM PUBLIC;
