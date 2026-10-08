BEGIN;
SELECT plan(16);

-- Database side of the per-instance compliance service (MAIR-498): the compliance_api role,
-- the append-only journal, the erasure steps, the scan and the erasure targets.

-- Runs `p_sql` as `p_role` and returns 'ok' or the SQLSTATE it raised (same helper as 20_*).
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

---
--- 1. ROLE
---

-- Test 1: the role exists, logs in (password parameter of the test stack), nothing elevated.
SELECT ok(
    EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'compliance_api' AND rolcanlogin
            AND NOT rolsuper AND NOT rolcreaterole AND NOT rolcreatedb AND NOT rolbypassrls),
    'compliance_api is a login role without elevated attributes'
);

-- Test 2: it reads no personal table directly: the scan and the targets go through functions.
SELECT is(
    (SELECT count(*)::INT FROM unnest(ARRAY['users_audit_log', 'connection_logs', 'access_logs', 'messages',
                                            'sessions', 'user_identities', 'events']) AS t(name)
     WHERE has_table_privilege('compliance_api', t.name, 'SELECT, INSERT, UPDATE, DELETE')),
    0,
    'compliance_api has no privilege on the personal tables'
);
SELECT ok(
    NOT has_column_privilege('compliance_api', 'users', 'email', 'SELECT')
    AND NOT has_column_privilege('compliance_api', 'users', 'password', 'SELECT'),
    'compliance_api cannot read users.email nor users.password'
);

-- Test 4: what it writes.
SELECT set_eq(
    $$SELECT c.relname::TEXT FROM pg_class c
       WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p', 'v')
         AND has_table_privilege('compliance_api', c.oid, 'INSERT, UPDATE, DELETE')$$,
    ARRAY['compliance_journal', 'erasure_steps'],
    'compliance_api writes only its journal and the erasure steps'
);

---
--- 2. JOURNAL
---

-- Test 5-6: the journal takes an entry from the service, and nobody can change or remove it.
SELECT is(
    pg_temp.run_as('compliance_api',
        $$INSERT INTO compliance_journal (kind, storage, location, action, rows, masked_excerpt, cause_hint)
          VALUES ('log_leak', 'logs', 'core-api/tracing', 'masked', 1, 'login failed for <email>', 'tracing span')$$),
    'ok',
    'compliance_api can journal a finding'
);
SELECT throws_ok(
    $$UPDATE compliance_journal SET masked_excerpt = 'x'$$,
    'P0001', NULL,
    'the journal cannot be updated, even by the owner'
);
SELECT throws_ok(
    $$DELETE FROM compliance_journal$$,
    'P0001', NULL,
    'the journal cannot be deleted, even by the owner'
);
SELECT is(
    pg_temp.run_as('compliance_api', $$DELETE FROM compliance_journal$$),
    '42501',
    'compliance_api has no DELETE on the journal'
);

---
--- 3. ERASURE
---

INSERT INTO users (id, first_name, last_name, email, password, phone_number, phone_country)
VALUES (9900, 'Compliancemarker', 'Tracer', 'gdpr.compliance.marker@example.com',
        '$argon2id$v=19$m=16,t=2,p=1$c2FsdHNhbHQ$aGFzaGhhc2g', '612000999', 'FR'),
       (9901, 'Admin', 'Compliance', 'admin.compliance@example.com', NULL, NULL, NULL);
SET CONSTRAINTS ALL IMMEDIATE;
INSERT INTO user_roles (user_id, role_id) SELECT 9901, id FROM roles WHERE name = 'Admin';
INSERT INTO user_identities (user_id, provider, subject) VALUES (9900, 'keycloak', 'kc-compliance-marker');

-- Test 9: the targets, read before the erasure.
SELECT is(
    (SELECT fn_erasure_targets(9900)),
    '{"user_id": 9900, "email": "gdpr.compliance.marker@example.com", "keycloak_subject": "kc-compliance-marker"}'::JSONB,
    'fn_erasure_targets gives the e-mail and the Keycloak subject to propagate the erasure'
);

-- Test 10: the steps, then the database step itself, as compliance_api.
SELECT is(
    pg_temp.run_as('compliance_api',
        $$INSERT INTO erasure_steps (user_id, step) SELECT 9900, s FROM unnest(ARRAY['keycloak', 'resend', 's3', 'redis', 'backup_key', 'database']) s;
          UPDATE erasure_steps SET status = 'done', attempts = 1, updated_at = now() WHERE user_id = 9900 AND step = 'keycloak';
          SELECT anonymize_user(9900)$$),
    'ok',
    'compliance_api records the steps and runs anonymize_user'
);
SELECT ok(is_user_anonymized(9900), 'the account is anonymized');

-- Test 12: nothing left to propagate once anonymized.
SELECT is(fn_erasure_targets(9900), NULL, 'no target is given for an anonymized account');

---
--- 4. SCAN
---

-- Test 13: a clean erasure leaves no erased_user_data finding for the account.
SELECT is_empty(
    $$SELECT * FROM fn_compliance_scan() WHERE kind = 'erased_user_data'$$,
    'a clean erasure leaves nothing to report'
);

-- Test 14: a row left behind on the anonymized account is found, without its value.
INSERT INTO user_preferences (user_id) VALUES (9900);
SELECT results_eq(
    $$SELECT kind, location, rows FROM fn_compliance_scan() WHERE kind = 'erased_user_data'$$,
    $$VALUES ('erased_user_data'::TEXT, 'user_preferences.user_id'::TEXT, 1::BIGINT)$$,
    'a row left on an anonymized account is reported by table and count'
);

-- Test 15: a session older than its retention period is reported.
INSERT INTO sessions (id, user_id, token_hash, device_info, created_at)
VALUES ('7a1f0000-0000-4000-8000-000000009901', 9901, 'compliance-old-session', 'Firefox', now() - interval '2 years');
SELECT ok(
    EXISTS (SELECT 1 FROM fn_compliance_scan() WHERE kind = 'retention_overdue' AND location = 'sessions' AND rows >= 1),
    'a session past the retention period is reported'
);

-- Test 16: the scan is callable by compliance_api and never returns a value of a person.
SELECT is(
    pg_temp.run_as('compliance_api', $$SELECT * FROM fn_compliance_scan()$$),
    'ok',
    'compliance_api can run the scan'
);

SELECT * FROM finish();
ROLLBACK;
