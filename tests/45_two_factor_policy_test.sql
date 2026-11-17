BEGIN;
SELECT plan(17);

-- Two-factor policy of the instance (MAIR-808): releases/v3.6.0/01. One row, Core reads and updates it,
-- every change is audited by a trigger, at least one mode stays allowed.

INSERT INTO users (id, first_name, last_name, email, password)
VALUES (9960, 'Policy', 'Admin', 'policy.admin@example.com', NULL);

SELECT has_table('two_factor_policy', 'two_factor_policy exists');
SELECT has_table('two_factor_policy_audit_log', 'two_factor_policy_audit_log exists');

-- Initial value: optional, TOTP and backup codes allowed, passkeys not yet.
SELECT is((SELECT count(*)::INT FROM two_factor_policy), 1, 'the policy has its single row');
SELECT results_eq(
    $$SELECT required, totp_allowed, passkey_allowed, backup_codes_allowed, updated_by FROM two_factor_policy$$,
    $$VALUES (FALSE, TRUE, FALSE, TRUE, NULL::INT)$$,
    'initial policy: second factor optional, TOTP and backup codes allowed'
);

-- One row only, never deleted.
SELECT throws_ok($$INSERT INTO two_factor_policy (id) VALUES (2)$$, '23514', NULL, 'no second row');
SELECT throws_ok($$DELETE FROM two_factor_policy$$, 'P0001', NULL, 'the row cannot be deleted');

-- Validity.
SELECT throws_ok(
    $$UPDATE two_factor_policy SET totp_allowed = FALSE, passkey_allowed = FALSE$$,
    '23514', NULL, 'at least one mode must stay allowed'
);
SELECT throws_ok(
    $$UPDATE two_factor_policy SET totp_allowed = FALSE$$,
    '23514', NULL, 'passkeys are off, so TOTP cannot be removed alone'
);

-- A change is audited with its author, before and after.
SELECT is((SELECT count(*)::INT FROM two_factor_policy_audit_log), 0, 'nothing audited before a change');
SELECT lives_ok(
    $$UPDATE two_factor_policy SET required = TRUE, updated_by = 9960, updated_at = now()$$,
    'the administrator makes the second factor mandatory'
);
SELECT is((SELECT count(*)::INT FROM two_factor_policy_audit_log), 1, 'the change is audited');
SELECT results_eq(
    $$SELECT action_by, (previous_data ->> 'required')::BOOLEAN, (new_data ->> 'required')::BOOLEAN
      FROM two_factor_policy_audit_log$$,
    $$VALUES (9960, FALSE, TRUE)$$,
    'the audit keeps the author, the previous and the new value'
);

-- The audit log is append-only.
SELECT throws_ok($$UPDATE two_factor_policy_audit_log SET action_by = 1$$, 'P0001', NULL, 'audit rows cannot be rewritten');
SELECT throws_ok($$DELETE FROM two_factor_policy_audit_log$$, 'P0001', NULL, 'audit rows cannot be deleted');

-- Privileges: Core reads and updates the policy, nobody else touches it, nobody reads the audit log.
SELECT results_eq(
    $$SELECT r.name FROM unnest(ARRAY['core_api', 'project_api', 'calendar_api', 'message_api', 'elearning_api', 'compliance_api']) AS r(name)
      WHERE has_table_privilege(r.name, 'two_factor_policy', 'SELECT') ORDER BY 1$$,
    $$VALUES ('core_api')$$,
    'only core_api reads the policy'
);
SELECT results_eq(
    $$SELECT r.name FROM unnest(ARRAY['core_api', 'project_api', 'calendar_api', 'message_api', 'elearning_api', 'compliance_api']) AS r(name)
      WHERE has_table_privilege(r.name, 'two_factor_policy_audit_log', 'SELECT')
         OR has_table_privilege(r.name, 'two_factor_policy_audit_log', 'INSERT')$$,
    $$SELECT NULL::TEXT WHERE FALSE$$,
    'no API role has any privilege on the audit log'
);
SELECT ok(
    NOT has_table_privilege('core_api', 'two_factor_policy', 'INSERT')
    AND NOT has_table_privilege('core_api', 'two_factor_policy', 'DELETE'),
    'core_api updates the policy but never inserts or deletes it'
);

SELECT * FROM finish();
ROLLBACK;
