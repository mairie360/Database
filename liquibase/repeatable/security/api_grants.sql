-- Privileges of the per-API roles created in security/api_roles.sql (MAIR-114).
--
-- Each API gets full DML on the tables of its own domain, and read-only
-- access (column-level where possible) to the few tables of other domains its
-- queries actually read. Scopes were derived from the SQL of APIs/Core_API,
-- Project_API, Calendar_API, Message_API, ELearning_API and API_lib.
--
-- This file is the single source of truth: it first revokes everything the
-- API roles hold in `public`, then grants again, and runs on every update so
-- tables recreated by a release get their grants back. A new table is NOT
-- reachable by any API until it is added here.
--
-- Logging, audit and cross-domain cleanup happen in SECURITY DEFINER
-- functions (check_access, is_admin, session/audit log triggers,
-- fn_archive_user, fn_check_can_delete_user, fn_set_group_accesses), so no API
-- needs access to users_audit_log, connection_logs, access_logs, or to
-- another domain's tables just because one of its statements fires a trigger.

-- ---------------------------------------------------------------------------
-- Reset
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_role TEXT;
BEGIN
    FOREACH v_role IN ARRAY ARRAY['core_api', 'project_api', 'calendar_api', 'message_api', 'elearning_api']
    LOOP
        -- ALL TABLES covers views too, and revoking a table privilege also
        -- revokes the matching column privileges.
        EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM %I', v_role);
        EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM %I', v_role);
        EXECUTE format('REVOKE CREATE ON SCHEMA public FROM %I', v_role);
        EXECUTE format('GRANT USAGE ON SCHEMA public TO %I', v_role);
        EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), v_role);
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Shared by every API
-- ---------------------------------------------------------------------------
-- API_lib JwtMiddleware checks that the token's user exists (DoesUserExistById).
GRANT SELECT (id) ON users TO core_api, project_api, calendar_api, message_api, elearning_api;
-- check_access() and is_admin() are SECURITY DEFINER and executable by
-- PUBLIC (the default), so RightMiddleware / AdminMiddleware work for every
-- API without reading the RBAC tables.

-- ---------------------------------------------------------------------------
-- core_api: users, auth, sessions, roles, groups, RBAC and ACL
-- ---------------------------------------------------------------------------
-- Users are never hard-deleted: archiving goes through UPDATE or v_users_active.
GRANT SELECT, INSERT, UPDATE ON users TO core_api;
GRANT SELECT, DELETE ON v_users_active TO core_api;
GRANT SELECT ON v_users_archived TO core_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_preferences, user_notification_settings TO core_api;
-- SSO identities (MAIR-141): the login path resolves a Keycloak subject and
-- the migration job links accounts through link_user_identity(), both as
-- core_api. v_users_sso_export is what the job reads to provision Keycloak.
GRANT SELECT, INSERT, UPDATE, DELETE ON user_identities TO core_api;
GRANT SELECT ON v_users_sso_export TO core_api;

GRANT SELECT, INSERT, UPDATE, DELETE ON sessions TO core_api;
GRANT SELECT ON v_sessions, session_settings TO core_api;

GRANT SELECT, INSERT, UPDATE, DELETE ON roles, user_roles TO core_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON groups, group_members TO core_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON access_control TO core_api;
GRANT SELECT ON resources, permissions, rights TO core_api;
GRANT SELECT ON v_securable_users, v_securable_roles, v_securable_sessions,
    v_securable_session_settings, v_securable_groups TO core_api;

-- IsOwnerQueryView reads `owner_id` of any securable resource before an ACL
-- is granted on it; `events` is the only one outside core's domain.
GRANT SELECT (id, owner_id) ON events TO core_api;

-- ---------------------------------------------------------------------------
-- project_api: projects and tasks
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON projects, project_members, tasks,
    task_assignees, task_history TO project_api;

-- Author names, manager roles and team (group) visibility.
GRANT SELECT (id, first_name, last_name) ON users TO project_api;
GRANT SELECT ON roles, user_roles, group_members TO project_api;

-- ---------------------------------------------------------------------------
-- calendar_api: events and recurrences
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON events, event_members, recurrence_rules,
    recurrence_members, user_calendar_params TO calendar_api;
GRANT SELECT ON v_securable_events TO calendar_api;

-- Member validation, manager roles and shared groups.
GRANT SELECT (id, is_archived) ON users TO calendar_api;
GRANT SELECT ON roles, user_roles, group_members TO calendar_api;

-- ---------------------------------------------------------------------------
-- message_api: conversations and messages
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON conversations, conversation_members,
    messages, unread_counters, message_mentions, message_business_links TO message_api;

-- Group conversations notify every member of the group
-- (fn_auto_increment_unread_counter).
GRANT SELECT ON group_members TO message_api;

-- ---------------------------------------------------------------------------
-- elearning_api: courses and learner progress
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON courses, course_modules, course_attachments,
    course_ratings, user_courses, user_modules, user_content_progress TO elearning_api;

-- Learner list for the admin screens.
GRANT SELECT (id, first_name, last_name, is_archived) ON users TO elearning_api;

-- ---------------------------------------------------------------------------
-- Sequences: USAGE on the SERIAL / identity sequences of every table a role
-- can INSERT into.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_seq RECORD;
BEGIN
    FOR v_seq IN
        SELECT DISTINCT seq.oid::regclass AS seq_name, r.rolname
        FROM pg_class tbl
        JOIN pg_depend dep
          ON dep.refobjid = tbl.oid
         AND dep.refclassid = 'pg_class'::regclass
         AND dep.classid = 'pg_class'::regclass
         AND dep.deptype IN ('a', 'i')
        JOIN pg_class seq ON seq.oid = dep.objid AND seq.relkind = 'S'
        CROSS JOIN pg_roles r
        WHERE tbl.relnamespace = 'public'::regnamespace
          AND tbl.relkind IN ('r', 'p')
          AND r.rolname IN ('core_api', 'project_api', 'calendar_api', 'message_api', 'elearning_api')
          AND has_table_privilege(r.rolname, tbl.oid, 'INSERT')
    LOOP
        EXECUTE format('GRANT USAGE ON SEQUENCE %s TO %I', v_seq.seq_name, v_seq.rolname);
    END LOOP;
END;
$$;
