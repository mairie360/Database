BEGIN;
SELECT plan(11);

-- MAIR-477: lint findings dropped and trigram indexes for the user searches
-- (releases/v3.0.0, repeatable/users/trigger_user_update.sql).

-- Plan of `p_sql`, one line per row of EXPLAIN, joined.
CREATE FUNCTION pg_temp.plan_of(p_sql TEXT) RETURNS TEXT AS $$
DECLARE
    v_line TEXT;
    v_plan TEXT := '';
BEGIN
    FOR v_line IN EXECUTE 'EXPLAIN (COSTS OFF) ' || p_sql LOOP
        v_plan := v_plan || v_line || E'\n';
    END LOOP;
    RETURN v_plan;
END;
$$ LANGUAGE plpgsql;

SELECT has_extension('pg_trgm', 'pg_trgm is installed');

SELECT has_index('users', 'idx_users_first_name_trgm', 'Trigram index on users.first_name');
SELECT has_index('users', 'idx_users_last_name_trgm', 'Trigram index on users.last_name');
SELECT has_index('users', 'idx_users_email_trgm', 'Trigram index on users.email');
SELECT has_index('users', 'idx_users_first_last_name_trgm', 'Trigram index on first_name || '' '' || last_name');
SELECT has_index('users', 'idx_users_last_first_name_trgm', 'Trigram index on last_name || '' '' || first_name');

SELECT hasnt_trigger('users', 'trg_users_updated_at', 'The duplicate trg_users_updated_at is dropped');
SELECT has_trigger('users', 'tr_10_users_updated_at', 'tr_10_users_updated_at still refreshes updated_at');

SELECT hasnt_index('user_roles', 'idx_user_roles_user', 'Redundant idx_user_roles_user is dropped');

-- The search of Core_API (users/list_directory, admin/list_users) must be able
-- to use an index on every branch of its OR, the full names included: the
-- expressions of the indexes have to be the ones the APIs write. Sequential
-- scans are disabled so the plan does not depend on the size of the test data.
-- With them disabled, the planner walks the whole B-tree of releases/v3.0.1
-- (idx_users_name_order) rather than any other index on the handful of test rows:
-- it is dropped in this transaction, rolled back at the end, so these plans only
-- tell whether the trigram indexes serve the searches.
DROP INDEX idx_users_name_order;
SET LOCAL enable_seqscan = off;

SELECT unalike(
    pg_temp.plan_of($$
        SELECT id FROM users u
        WHERE u.first_name ILIKE '%martin%' OR u.last_name ILIKE '%martin%'
           OR (u.first_name || ' ' || u.last_name) ILIKE '%martin%'
           OR (u.last_name || ' ' || u.first_name) ILIKE '%martin%'
           OR u.email ILIKE '%martin%'
    $$),
    '%Seq Scan on users%',
    'The admin search (both name orders) uses the trigram indexes'
);

SELECT alike(
    pg_temp.plan_of($$
        SELECT id FROM users u
        WHERE (u.first_name || ' ' || u.last_name) ILIKE '%jean mart%'
    $$),
    '%idx_users_first_last_name_trgm%',
    'A full-name search uses idx_users_first_last_name_trgm'
);

SELECT * FROM finish();
ROLLBACK;
