BEGIN;
SELECT plan(22);

-- Every replaced refresh token of a session and the report of their reuse (MAIR-776):
-- releases/v4.0.0/22 and repeatable/sessions/fn_session_security.sql.

INSERT INTO users (id, first_name, last_name, email, password)
VALUES (9990, 'Refresh', 'Owner', 'refresh.owner@example.com', NULL);
INSERT INTO sessions (id, user_id, token_hash, device_info, ip_address)
VALUES ('00000000-0000-4000-8000-000000009990', 9990, 'mair776_a1', 'Firefox', '92.184.20.1'),
       ('00000000-0000-4000-8000-000000009991', 9990, 'mair776_b1', 'Chrome', '92.184.20.2'),
       ('00000000-0000-4000-8000-000000009992', 9990, 'mair776_c1', 'Safari', '92.184.20.3');

-- Schema
SELECT has_table('session_replaced_refresh_tokens', 'session_replaced_refresh_tokens exists');
SELECT ok(
    'REFRESH_REUSE' = ANY (enum_range(NULL::session_action)::TEXT[]),
    'MAIR-776 the session log knows REFRESH_REUSE'
);
SELECT lives_ok(
    $$INSERT INTO connection_logs (user_id, session_id, timestamp, action_type)
      VALUES (9990, '00000000-0000-4000-8000-000000009990', now(), 'REFRESH_REUSE')$$,
    'MAIR-776 REFRESH_REUSE is accepted in connection_logs'
);
SELECT ok(
    NOT has_table_privilege('core_api', 'session_replaced_refresh_tokens', 'SELECT')
        AND NOT has_table_privilege('core_api', 'session_replaced_refresh_tokens', 'INSERT'),
    'no API role reaches the replaced hashes directly'
);

-- Every rotation keeps the hash it replaced
UPDATE sessions SET token_hash = 'mair776_a2' WHERE id = '00000000-0000-4000-8000-000000009990';
UPDATE sessions SET token_hash = 'mair776_a3' WHERE id = '00000000-0000-4000-8000-000000009990';
UPDATE sessions SET token_hash = 'mair776_a4' WHERE id = '00000000-0000-4000-8000-000000009990';
SELECT results_eq(
    $$SELECT token_hash FROM session_replaced_refresh_tokens
      WHERE session_id = '00000000-0000-4000-8000-000000009990' ORDER BY token_hash$$,
    $$VALUES ('mair776_a1'), ('mair776_a2'), ('mair776_a3')$$,
    'MAIR-776 the hashes of every rotation are kept, not only the last one'
);
UPDATE sessions SET device_info = 'Firefox 2' WHERE id = '00000000-0000-4000-8000-000000009990';
SELECT is(
    (SELECT count(*)::INT FROM session_replaced_refresh_tokens WHERE session_id = '00000000-0000-4000-8000-000000009990'),
    3,
    'an update that keeps the token keeps nothing'
);

-- Unknown hash
SELECT is(
    report_refresh_token_reuse('mair776_unknown', 10, '81.250.2.1', 'curl')->>'known',
    'false',
    'MAIR-776 an unknown hash is not a reuse'
);

-- Within the grace window: concurrent renewal, nothing written
SELECT is(
    report_refresh_token_reuse('mair776_a3', 10, '92.184.20.1', 'Firefox'),
    jsonb_build_object('known', TRUE, 'superseded', TRUE, 'reused', FALSE, 'revoked', FALSE,
                       'session_id', '00000000-0000-4000-8000-000000009990', 'user_id', 9990, 'alert_id', NULL),
    'MAIR-776 a hash replaced within the window is superseded'
);
SELECT is(
    (SELECT revoked_at FROM sessions WHERE id = '00000000-0000-4000-8000-000000009990'),
    NULL,
    'MAIR-776 a superseded token leaves the session open'
);
SELECT is(
    (SELECT count(*)::INT FROM session_security_alerts WHERE session_id = '00000000-0000-4000-8000-000000009990'),
    0,
    'MAIR-776 a superseded token raises no alert'
);

-- After the window: the session is closed, logged and an alert queued
UPDATE session_replaced_refresh_tokens SET replaced_at = now() - interval '1 minute'
WHERE token_hash = 'mair776_a1';
CREATE TEMP TABLE mair776_report AS
SELECT report_refresh_token_reuse('mair776_a1', 10, '81.250.2.2', 'Thief browser') AS r;
SELECT is(
    (SELECT r - 'alert_id' FROM mair776_report),
    jsonb_build_object('known', TRUE, 'superseded', FALSE, 'reused', TRUE, 'revoked', TRUE,
                       'session_id', '00000000-0000-4000-8000-000000009990', 'user_id', 9990),
    'MAIR-776 a token replaced three rotations ago is a reuse'
);
SELECT isnt(
    (SELECT revoked_at FROM sessions WHERE id = '00000000-0000-4000-8000-000000009990'),
    NULL,
    'MAIR-776 the reuse closes the session'
);
SELECT results_eq(
    $$SELECT ip_address, device_info FROM connection_logs
      WHERE session_id = '00000000-0000-4000-8000-000000009990' AND action_type = 'REFRESH_REUSE'
        AND ip_address IS NOT NULL$$,
    $$VALUES ('81.250.2.2'::INET, 'Thief browser'::TEXT)$$,
    'MAIR-776 the reuse is logged with the address and the device'
);
SELECT results_eq(
    $$SELECT id, level, ip_address FROM session_security_alerts WHERE session_id = '00000000-0000-4000-8000-000000009990'$$,
    $$SELECT (r->>'alert_id')::BIGINT, 'certain'::TEXT, '81.250.2.2'::INET FROM mair776_report$$,
    'MAIR-776 one certain alert is queued for the agent and the administrators'
);

-- Replayed again: logged, but no second alert and nothing to revoke
SELECT is(
    report_refresh_token_reuse('mair776_a1', 10, '81.250.2.2', 'Thief browser') - 'session_id' - 'user_id',
    jsonb_build_object('known', TRUE, 'superseded', FALSE, 'reused', TRUE, 'revoked', FALSE, 'alert_id', NULL),
    'MAIR-776 a second replay revokes nothing more'
);
SELECT is(
    (SELECT count(*)::INT FROM session_security_alerts WHERE session_id = '00000000-0000-4000-8000-000000009990'),
    1,
    'MAIR-776 a second replay sends no second alert'
);
SELECT is(
    (SELECT count(*)::INT FROM connection_logs
     WHERE session_id = '00000000-0000-4000-8000-000000009990' AND action_type = 'REFRESH_REUSE' AND ip_address IS NOT NULL),
    2,
    'MAIR-776 every replay is logged'
);

-- A recent hash of a session already closed is not superseded: the front has nothing to read again
UPDATE sessions SET token_hash = 'mair776_b2' WHERE id = '00000000-0000-4000-8000-000000009991';
UPDATE sessions SET revoked_at = now() WHERE id = '00000000-0000-4000-8000-000000009991';
SELECT is(
    report_refresh_token_reuse('mair776_b1', 10, NULL, NULL)->>'superseded',
    'false',
    'MAIR-776 a recent hash of a closed session is not superseded'
);

-- Bad window
SELECT throws_ok(
    $$SELECT report_refresh_token_reuse('mair776_b1', -1, NULL, NULL)$$,
    '22023', NULL, 'a negative grace window is refused'
);

-- Privileges
SELECT ok(
    has_function_privilege('core_api', 'report_refresh_token_reuse(text, integer, inet, text)', 'EXECUTE'),
    'core_api reports a reuse'
);
SELECT ok(
    NOT has_function_privilege('project_api', 'report_refresh_token_reuse(text, integer, inet, text)', 'EXECUTE'),
    'the other APIs do not'
);

-- The hashes go with their session
UPDATE sessions SET token_hash = 'mair776_c2' WHERE id = '00000000-0000-4000-8000-000000009992';
DELETE FROM sessions WHERE id = '00000000-0000-4000-8000-000000009992';
SELECT is(
    (SELECT count(*)::INT FROM session_replaced_refresh_tokens WHERE token_hash = 'mair776_c1'),
    0,
    'MAIR-776 the replaced hashes are deleted with their session'
);

SELECT * FROM finish();
ROLLBACK;
