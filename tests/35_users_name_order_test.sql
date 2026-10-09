BEGIN;
SELECT plan(2);

-- MAIR-477 (releases/v3.1.0): index on the order of Core_API's admin user list.

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

SELECT has_index(
    'users', 'idx_users_name_order', ARRAY['last_name', 'first_name', 'id'],
    'B-tree on the order of the admin user list'
);

-- A page of the list without search walks the index instead of sorting every user.
-- Sequential scans are disabled so the plan does not depend on the size of the test data.
SET LOCAL enable_seqscan = off;

SELECT alike(
    pg_temp.plan_of($$
        SELECT id FROM users u ORDER BY u.last_name, u.first_name, u.id LIMIT 20 OFFSET 100
    $$),
    '%idx_users_name_order%',
    'A page of the admin user list is read in index order'
);

SELECT * FROM finish();
