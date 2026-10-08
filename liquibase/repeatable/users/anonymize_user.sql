-- Erasure and export of a user's data (MAIR-289, epic MAIR-284), following the `erasure` of each
-- column in gdpr/inventory.yaml:
--   delete     the rows of the user (memberships, sessions, preferences, roles, identities...) go;
--   anonymize  the users row stays, without its identity (names, e-mail, phone, photo, biography,
--              password): the references of shared objects (messages, comments, tasks, events)
--              keep pointing to it and no longer name anyone; the identity copied into
--              users_audit_log is replaced by a hash;
--   keep       records kept on purpose (security logs, training records, moderation evidence).
-- Owned objects (decisions of MAIR-289): the private events of the user are deleted, the other
-- events, the groups and the projects are handed over to an administrator. Direct conversations
-- stay for the other participant.
--
-- tests/37_gdpr_erasure_test.sql checks that no value of an anonymized user remains in any text or
-- JSON column, and that the export covers every identifier column of the inventory.

DROP FUNCTION IF EXISTS fn_pseudonymize_identity(JSONB, INT);
DROP FUNCTION IF EXISTS anonymize_user(INT);
DROP FUNCTION IF EXISTS fn_anonymize_archived_users(INTERVAL);
DROP FUNCTION IF EXISTS export_user_data(INT);
DROP FUNCTION IF EXISTS is_user_anonymized(INT);

-- The identity keys of a users row copy (users_audit_log.previous_data / new_data), each replaced by
-- `sha256:<hex>` of the user id, the key and the value: the record of what happened stays, it no
-- longer says who the person was.
CREATE OR REPLACE FUNCTION fn_pseudonymize_identity(p_data JSONB, p_user_id INT)
RETURNS JSONB AS $$
DECLARE
    v_key TEXT;
    v_out JSONB := p_data;
BEGIN
    IF p_data IS NULL THEN
        RETURN NULL;
    END IF;
    FOREACH v_key IN ARRAY ARRAY['first_name', 'last_name', 'email', 'phone_number', 'phone_country', 'photo', 'biography', 'password']
    LOOP
        IF v_out ? v_key AND jsonb_typeof(v_out -> v_key) <> 'null'
           AND (v_out ->> v_key) NOT LIKE 'sha256:%' THEN
            v_out := jsonb_set(v_out, ARRAY[v_key], to_jsonb('sha256:' || encode(sha256(
                convert_to(p_user_id || ':' || v_key || ':' || (v_out ->> v_key), 'UTF8')), 'hex')));
        END IF;
    END LOOP;
    RETURN v_out;
END;
$$ LANGUAGE plpgsql IMMUTABLE SET search_path = public, pg_temp;

-- An anonymized account carries this e-mail: the marker that it was erased (no extra column, so that
-- v_users_active / v_users_archived, which select users.*, do not change).
CREATE OR REPLACE FUNCTION is_user_anonymized(p_user_id INT)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND email = format('anonymized-%s@anonymized.invalid', id));
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

-- Erases the user `p_user_id` (archived first if needed) and returns what was done:
-- { user_id, already_anonymized, handed_over_to, deleted_private_events, revoked_sessions[] }.
-- The caller (Core_API) publishes `revoked_sessions` to the revocation list (MAIR-264) and mirrors
-- the erasure to Keycloak. Refused for the seeded administrator (id 1) and when no other active
-- administrator can take the objects over.
CREATE OR REPLACE FUNCTION anonymize_user(p_user_id INT)
RETURNS JSONB AS $$
DECLARE
    v_admin INT;
    v_sessions UUID[];
    v_events INT;
BEGIN
    IF p_user_id = 1 THEN
        RAISE EXCEPTION 'The seeded administrator (id 1) cannot be anonymized' USING ERRCODE = 'restrict_violation';
    END IF;
    PERFORM 1 FROM users WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % does not exist', p_user_id USING ERRCODE = 'no_data_found';
    END IF;
    IF is_user_anonymized(p_user_id) THEN
        RETURN jsonb_build_object('user_id', p_user_id, 'already_anonymized', TRUE);
    END IF;

    SELECT min(ur.user_id) INTO v_admin
    FROM user_roles ur
    JOIN roles r ON r.id = ur.role_id
    JOIN users u ON u.id = ur.user_id
    WHERE r.name = 'Admin' AND u.is_archived IS NOT TRUE AND u.id <> p_user_id;
    IF v_admin IS NULL THEN
        RAISE EXCEPTION 'No other active administrator can take over the objects of user %', p_user_id
            USING ERRCODE = 'restrict_violation';
    END IF;

    SELECT coalesce(array_agg(id), '{}') INTO v_sessions FROM sessions WHERE user_id = p_user_id;

    -- Owned objects.
    DELETE FROM events WHERE owner_id = p_user_id AND visibility = 'private';
    GET DIAGNOSTICS v_events = ROW_COUNT;
    UPDATE events SET owner_id = v_admin WHERE owner_id = p_user_id;
    UPDATE groups SET owner_id = v_admin WHERE owner_id = p_user_id;
    UPDATE projects SET owner_id = v_admin WHERE owner_id = p_user_id;

    -- erasure: delete
    DELETE FROM access_control WHERE user_id = p_user_id;
    DELETE FROM conversation_members WHERE user_id = p_user_id;
    DELETE FROM conversation_read_cursors WHERE user_id = p_user_id;
    DELETE FROM course_ratings WHERE user_id = p_user_id;
    DELETE FROM event_members WHERE user_id = p_user_id;
    DELETE FROM group_members WHERE user_id = p_user_id;
    DELETE FROM message_mentions WHERE user_id = p_user_id;
    DELETE FROM project_members WHERE user_id = p_user_id;
    DELETE FROM recurrence_members WHERE user_id = p_user_id;
    DELETE FROM sessions WHERE user_id = p_user_id;
    DELETE FROM task_assignees WHERE user_id = p_user_id;
    DELETE FROM unread_counters WHERE user_id = p_user_id;
    DELETE FROM user_calendar_params WHERE user_id = p_user_id;
    DELETE FROM user_content_progress WHERE user_id = p_user_id;
    DELETE FROM user_identities WHERE user_id = p_user_id;
    DELETE FROM user_modules WHERE user_id = p_user_id;
    DELETE FROM user_notification_settings WHERE user_id = p_user_id;
    DELETE FROM user_preferences WHERE user_id = p_user_id;

    -- Archived (fn_archive_user cleans what is left), then without identity. The roles go after the
    -- archiving: restore_user() of an anonymized account is refused anyway.
    UPDATE users SET is_archived = TRUE, status = 'archived' WHERE id = p_user_id AND is_archived IS NOT TRUE;
    DELETE FROM user_roles WHERE user_id = p_user_id;
    UPDATE users
    SET first_name = 'Anonymized',
        last_name = 'User',
        email = format('anonymized-%s@anonymized.invalid', id),
        password = NULL,
        phone_number = NULL,
        phone_country = NULL,
        photo = NULL,
        biography = NULL
    WHERE id = p_user_id;

    -- The audit rows of the user, the ones the two updates above just wrote included.
    PERFORM set_config('mairie360.audit_pseudonymize', 'on', TRUE);
    UPDATE users_audit_log
    SET previous_data = fn_pseudonymize_identity(previous_data, user_id),
        new_data = fn_pseudonymize_identity(new_data, user_id)
    WHERE user_id = p_user_id;
    PERFORM set_config('mairie360.audit_pseudonymize', 'off', TRUE);

    RETURN jsonb_build_object(
        'user_id', p_user_id,
        'already_anonymized', FALSE,
        'handed_over_to', v_admin,
        'deleted_private_events', v_events,
        'revoked_sessions', to_jsonb(v_sessions)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Anonymizes the accounts archived for longer than `p_older_than` (the `users` retention policy,
-- 1 year by default, set per instance), the archiving date being the last ARCHIVE of the audit log
-- (updated_at for an account archived before the audit existed). Returns how many were anonymized.
CREATE OR REPLACE FUNCTION fn_anonymize_archived_users(p_older_than INTERVAL)
RETURNS INT AS $$
DECLARE
    v_user RECORD;
    v_count INT := 0;
BEGIN
    FOR v_user IN
        SELECT u.id
        FROM users u
        WHERE u.is_archived IS TRUE
          AND u.id <> 1
          AND u.email <> format('anonymized-%s@anonymized.invalid', u.id)
          AND coalesce((SELECT max(a.action_date) FROM users_audit_log a
                        WHERE a.user_id = u.id AND a.action_type = 'ARCHIVE'), u.updated_at)
              < now() - p_older_than
        ORDER BY u.id
    LOOP
        PERFORM anonymize_user(v_user.id);
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Everything the schema attaches to the user, as JSON (right of access, GDPR art. 15):
-- { user: <users row>, data: { "<table>.<column>": [<rows where column = user>] } }
-- for every foreign key to users and the identifier columns without one (audit and moderation
-- logs). Credentials (password, token hashes) are left out; the photo is hex-encoded.
CREATE OR REPLACE FUNCTION export_user_data(p_user_id INT)
RETURNS JSONB AS $$
DECLARE
    v_ref RECORD;
    v_rows JSONB;
    v_data JSONB := '{}';
    v_user JSONB;
BEGIN
    SELECT to_jsonb(u) - 'password' INTO v_user FROM users u WHERE u.id = p_user_id;
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'User % does not exist', p_user_id USING ERRCODE = 'no_data_found';
    END IF;
    FOR v_ref IN
        SELECT c.conrelid::regclass::text AS table_name, a.attname::text AS column_name
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
        WHERE c.contype = 'f' AND c.confrelid = 'public.users'::regclass
          AND c.connamespace = 'public'::regnamespace AND NOT t.relispartition
        UNION
        SELECT * FROM (VALUES ('users_audit_log', 'user_id'), ('users_audit_log', 'action_by'),
                              ('messaging_moderation_log', 'target_user_id'),
                              ('messaging_moderation_log', 'performed_by')) AS extra(table_name, column_name)
        WHERE to_regclass('public.' || extra.table_name) IS NOT NULL
        ORDER BY 1, 2
    LOOP
        EXECUTE format(
            'SELECT coalesce(jsonb_agg(to_jsonb(t) - ARRAY[''password'', ''token_hash'']), ''[]'') FROM public.%I t WHERE t.%I = $1',
            v_ref.table_name, v_ref.column_name)
        INTO v_rows USING p_user_id;
        v_data := v_data || jsonb_build_object(v_ref.table_name || '.' || v_ref.column_name, v_rows);
    END LOOP;
    RETURN jsonb_build_object('user', v_user, 'data', v_data, 'exported_at', now());
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION anonymize_user(INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION export_user_data(INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_anonymize_archived_users(INTERVAL) FROM PUBLIC;
REVOKE ALL ON FUNCTION is_user_anonymized(INT) FROM PUBLIC;
