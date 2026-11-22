BEGIN;
SELECT plan(9);

-- Budget of a project (releases/v4.0.0/02, MAIR-1085): amounts voted and committed, in cents,
-- NULL until filled in, never negative. Project_API writes them.

CREATE FUNCTION pg_temp.run_as(p_role TEXT, p_sql TEXT) RETURNS TEXT AS $$
DECLARE
    v_result TEXT := 'ok';
BEGIN
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_result := SQLSTATE;
    END;
    RESET ROLE;
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

INSERT INTO users (id, first_name, last_name, email, password)
VALUES (5100, 'Bruno', 'Budget', 'bruno.budget@project-budget.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
INSERT INTO projects (id, title, owner_id) VALUES (5100, 'School roof', 5100);

--- 1. STRUCTURE (4 tests)
SELECT col_type_is('projects', 'budget_voted', 'bigint', 'the voted budget is a BIGINT amount in cents');
SELECT col_is_null('projects', 'budget_voted', 'the voted budget is optional');
SELECT col_type_is('projects', 'budget_committed', 'bigint', 'the committed budget is a BIGINT amount in cents');
SELECT col_is_null('projects', 'budget_committed', 'the committed budget is optional');

--- 2. VALUES (5 tests)
SELECT ok(
    (SELECT budget_voted IS NULL AND budget_committed IS NULL FROM projects WHERE id = 5100),
    'a project starts without budget'
);
SELECT is(
    pg_temp.run_as('project_api',
        $$UPDATE projects SET budget_voted = 12000000000, budget_committed = 0 WHERE id = 5100$$),
    'ok', 'project_api writes the budget (zero and amounts above 2^31 cents included)'
);
SELECT throws_ok(
    $$UPDATE projects SET budget_voted = -1 WHERE id = 5100$$,
    '23514', NULL, 'a negative voted budget is refused'
);
SELECT throws_ok(
    $$UPDATE projects SET budget_committed = -1 WHERE id = 5100$$,
    '23514', NULL, 'a negative committed budget is refused'
);
SELECT lives_ok(
    $$UPDATE projects SET budget_voted = NULL, budget_committed = NULL WHERE id = 5100$$,
    'the budget can be cleared'
);

SELECT * FROM finish();
ROLLBACK;
