-- MAIR-236: apply retention_policies. Nothing else reads that table but the
-- safety trigger, so the platform schedules fn_apply_retention_policies()
-- (e.g. a Kubernetes CronJob running as the database owner).

DROP FUNCTION IF EXISTS fn_ensure_access_logs_partitions(INT);

-- Creates one monthly partition of access_logs for the current month and the
-- next p_months_ahead ones. Rows already sitting in the DEFAULT partition for a
-- month are moved into its new partition first (ATTACH would refuse otherwise).
-- Returns the number of partitions created.
CREATE OR REPLACE FUNCTION fn_ensure_access_logs_partitions(p_months_ahead INT DEFAULT 3)
RETURNS INT AS $$
DECLARE
    v_month DATE;
    v_name TEXT;
    v_created INT := 0;
BEGIN
    IF p_months_ahead < 0 THEN
        RAISE EXCEPTION 'p_months_ahead must be >= 0, got %', p_months_ahead;
    END IF;

    -- Serialise concurrent callers (CronJob overlap, migration re-run).
    PERFORM pg_advisory_xact_lock(360, hashtext('access_logs_partitions'));

    FOR v_month IN
        SELECT generate_series(
            date_trunc('month', now())::date,
            (date_trunc('month', now()) + make_interval(months => p_months_ahead))::date,
            interval '1 month'
        )::date
    LOOP
        v_name := format('access_logs_y%sm%s', to_char(v_month, 'YYYY'), to_char(v_month, 'MM'));
        CONTINUE WHEN to_regclass(format('public.%I', v_name)) IS NOT NULL;

        EXECUTE format('CREATE TABLE public.%I (LIKE public.access_logs INCLUDING DEFAULTS INCLUDING CONSTRAINTS)', v_name);
        EXECUTE format(
            'WITH moved AS (DELETE FROM public.access_logs_default WHERE timestamp >= %L AND timestamp < %L RETURNING *)
             INSERT INTO public.%I SELECT * FROM moved',
            v_month, (v_month + interval '1 month')::date, v_name);
        EXECUTE format(
            'ALTER TABLE public.access_logs ATTACH PARTITION public.%I FOR VALUES FROM (%L) TO (%L)',
            v_name, v_month, (v_month + interval '1 month')::date);
        v_created := v_created + 1;
    END LOOP;

    RETURN v_created;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Applies every retention policy and returns what was done per table.
--   DELETE          sessions only (the one table with a cleanup rule)
--   PARTITION_DROP  access_logs only: drops monthly partitions that lie entirely
--                   before now() - retention_period; the DEFAULT partition is kept
--   COLD_STORAGE    skipped with a NOTICE: no cold-storage target exists yet
-- last_run is only updated for policies that were actually applied.
CREATE OR REPLACE FUNCTION fn_apply_retention_policies()
RETURNS TABLE (table_name TEXT, strategy TEXT, affected BIGINT) AS $$
DECLARE
    v_policy RECORD;
    v_cutoff TIMESTAMPTZ;
    v_part RECORD;
    v_affected BIGINT;
BEGIN
    PERFORM fn_ensure_access_logs_partitions();

    FOR v_policy IN SELECT * FROM retention_policies ORDER BY retention_policies.table_name LOOP
        v_cutoff := now() - v_policy.retention_period;
        v_affected := NULL;

        IF v_policy.strategy = 'DELETE' AND v_policy.table_name = 'sessions' THEN
            DELETE FROM sessions
            WHERE COALESCE(revoked_at, expires_at, created_at) < v_cutoff;
            GET DIAGNOSTICS v_affected = ROW_COUNT;

        ELSIF v_policy.strategy = 'PARTITION_DROP' AND v_policy.table_name = 'access_logs' THEN
            v_affected := 0;
            FOR v_part IN
                SELECT c.relname
                FROM pg_inherits i
                JOIN pg_class c ON c.oid = i.inhrelid
                WHERE i.inhparent = 'public.access_logs'::regclass
                  AND c.relname ~ '^access_logs_y[0-9]{4}m[0-9]{2}$'
            LOOP
                IF (to_date(substr(v_part.relname, 14, 4) || substr(v_part.relname, 19, 2), 'YYYYMM')
                    + interval '1 month') <= v_cutoff THEN
                    EXECUTE format('DROP TABLE public.%I', v_part.relname);
                    v_affected := v_affected + 1;
                END IF;
            END LOOP;

        ELSE
            RAISE NOTICE 'retention: strategy % is not applied for %', v_policy.strategy, v_policy.table_name;
        END IF;

        IF v_affected IS NOT NULL THEN
            UPDATE retention_policies rp SET last_run = now() WHERE rp.table_name = v_policy.table_name;
            table_name := v_policy.table_name;
            strategy := v_policy.strategy;
            affected := v_affected;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Maintenance functions: not callable by the API roles.
REVOKE ALL ON FUNCTION fn_ensure_access_logs_partitions(INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_apply_retention_policies() FROM PUBLIC;

-- Create the current and upcoming partitions at deploy time.
SELECT fn_ensure_access_logs_partitions();
