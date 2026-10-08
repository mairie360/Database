BEGIN;
SELECT plan(11);

-- MAIR-477: lint findings dropped (releases/v3.0.0, repeatable/users/trigger_user_update.sql)
-- and the trigram index of the user searches (releases/v3.0.1, which replaced the five of
-- releases/v3.0.0).

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

SELECT ok(
    EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'users'
            AND indexname = 'idx_users_search_text_trgm' AND indexdef LIKE '%gin_trgm_ops%'),
    'Trigram index on the search expression (releases/v3.0.1)'
);
SELECT hasnt_index('users', 'idx_users_first_name_trgm', 'Replaced by idx_users_search_text_trgm');
SELECT hasnt_index('users', 'idx_users_last_name_trgm', 'Replaced by idx_users_search_text_trgm');
SELECT hasnt_index('users', 'idx_users_email_trgm', 'Replaced by idx_users_search_text_trgm');
SELECT hasnt_index('users', 'idx_users_first_last_name_trgm', 'Replaced by idx_users_search_text_trgm');

SELECT hasnt_trigger('users', 'trg_users_updated_at', 'The duplicate trg_users_updated_at is dropped');
SELECT has_trigger('users', 'tr_10_users_updated_at', 'tr_10_users_updated_at still refreshes updated_at');

SELECT hasnt_index('user_roles', 'idx_user_roles_user', 'Redundant idx_user_roles_user is dropped');

-- The search of Core_API (users/list_directory, admin/list_users) matches one lowered
-- expression (releases/v3.0.1): it must be the expression of idx_users_search_text_trgm, or
-- every search reads the whole table. Sequential scans are disabled so the plan does not depend
-- on the size of the test data; with them disabled, the planner walks the whole B-tree
-- idx_users_name_order rather than any other index on the handful of test rows, so it is dropped
-- in this transaction (rolled back at the end).
DROP INDEX idx_users_name_order;
SET LOCAL enable_seqscan = off;

SELECT alike(
    pg_temp.plan_of($$
        SELECT id FROM users u
        WHERE lower(u.first_name || ' ' || u.last_name || chr(31)
                    || u.last_name || ' ' || u.first_name || chr(31)
                    || u.email) LIKE '%' || lower('Jean Mart') || '%'
    $$),
    '%idx_users_search_text_trgm%',
    'The search of Core_API uses idx_users_search_text_trgm'
);

SELECT is(
    (SELECT count(*)::int FROM (VALUES ('Jean', 'Martin', 'jm@x.fr')) v(f, l, e)
     WHERE lower(f || ' ' || l || chr(31) || l || ' ' || f || chr(31) || e)
           LIKE '%' || lower('martin jean') || '%'),
    1,
    'Both name orders are searchable'
);

SELECT * FROM finish();
