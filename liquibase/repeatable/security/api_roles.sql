-- One Postgres login role per API (MAIR-114). The postgres superuser stays
-- reserved to Liquibase; each API connects with its own role, whose
-- privileges are defined in security/api_grants.sql.
--
-- Passwords are Liquibase changelog parameters, passed by the migration job
-- as -D<role>_password (see Devops/Deploiment, charts/liquibase job.yaml).
-- This changeset runs on every update, so rotating a password in the secret
-- and re-running the migration is enough to apply it.
--
-- When a parameter is not supplied, Liquibase leaves the placeholder as-is:
-- the role is then created NOLOGIN if missing, and an existing role keeps
-- its current password. This keeps stacks that run the migrations without
-- parameters (API integration tests connect as postgres) working.
--
-- Each placeholder sits on its own line inside the $pwd$ quote on purpose:
-- when a "$" directly precedes a placeholder whose parameter is unset,
-- Liquibase treats it as an escape and drops that "$", breaking the quote.
DO $$
DECLARE
    v_role     RECORD;
    v_password TEXT;
    v_unset    BOOLEAN;
BEGIN
    FOR v_role IN
        SELECT * FROM (VALUES
            ('core_api',      $pwd$
                ${core_api_password}
            $pwd$),
            ('project_api',   $pwd$
                ${project_api_password}
            $pwd$),
            ('calendar_api',  $pwd$
                ${calendar_api_password}
            $pwd$),
            ('message_api',   $pwd$
                ${message_api_password}
            $pwd$),
            ('elearning_api', $pwd$
                ${elearning_api_password}
            $pwd$)
        ) AS r(name, password)
    LOOP
        v_password := btrim(v_role.password, E' \t\r\n');
        -- Built by concatenation so Liquibase does not substitute it.
        v_unset := v_password IS NULL
            OR v_password = ''
            OR left(v_password, 2) = '$' || '{';

        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role.name) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', v_role.name);
        END IF;

        -- API roles never own objects nor manage other roles.
        EXECUTE format(
            'ALTER ROLE %I NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',
            v_role.name
        );

        IF v_unset THEN
            RAISE NOTICE 'No password parameter for role %, password left unchanged.', v_role.name;
        ELSE
            EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', v_role.name, v_password);
        END IF;
    END LOOP;
END;
$$;
