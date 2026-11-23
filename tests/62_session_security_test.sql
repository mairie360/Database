BEGIN;
SELECT plan(24);

-- Session checks and stolen-session reports (MAIR-772, MAIR-773): releases/v4.0.0/20 and
-- repeatable/sessions/fn_session_security.sql.

INSERT INTO users (id, first_name, last_name, email, password)
VALUES (9980, 'Session', 'Owner', 'session.owner@example.com', NULL),
       (9981, 'Session', 'Other', 'session.other@example.com', NULL);
INSERT INTO sessions (id, user_id, token_hash, device_info, ip_address)
VALUES ('00000000-0000-4000-8000-000000009980', 9980, 'hash-9980-a', 'Firefox', '92.184.10.1'),
       ('00000000-0000-4000-8000-000000009981', 9980, 'hash-9980-b', 'Chrome', '92.184.10.2'),
       ('00000000-0000-4000-8000-000000009982', 9980, 'hash-9980-c', 'Safari', '92.184.10.3');

-- Schema
SELECT has_table('session_security_alerts', 'session_security_alerts exists');
SELECT has_column('sessions', 'dpop_jkt', 'a session carries the thumbprint of its device key');
SELECT throws_ok(
    $$UPDATE sessions SET dpop_jkt = 'not a thumbprint' WHERE id = '00000000-0000-4000-8000-000000009980'$$,
    '23514', NULL, 'a device key thumbprint is a base64url SHA-256'
);
SELECT lives_ok(
    $$UPDATE sessions SET dpop_jkt = repeat('a', 43) WHERE id = '00000000-0000-4000-8000-000000009981'$$,
    'a 43-character base64url thumbprint is accepted'
);
SELECT ok(
    ARRAY['STOLEN_SESSION_ATTEMPT', 'SUSPICIOUS_IP_CHANGE', 'IP_CHANGE']::TEXT[]
        <@ enum_range(NULL::session_action)::TEXT[],
    'the session log knows the three new actions'
);

-- session_state
SELECT results_eq(
    $$SELECT active, ip_address, dpop_jkt FROM session_state('00000000-0000-4000-8000-000000009981', 9980)$$,
    $$VALUES (TRUE, '92.184.10.2'::INET, repeat('a', 43))$$,
    'an active session answers active with its address and its device key'
);
SELECT is_empty(
    $$SELECT * FROM session_state('00000000-0000-4000-8000-000000009981', 9981)$$,
    'the session of another user answers nothing'
);
UPDATE users SET status = 'suspended' WHERE id = 9980;
SELECT is((SELECT active FROM session_state('00000000-0000-4000-8000-000000009980', 9980)), FALSE,
    'the session of a suspended account is not active');
UPDATE users SET status = 'offline' WHERE id = 9980;
SELECT is((SELECT active FROM session_state('00000000-0000-4000-8000-000000009980', 9980)), TRUE,
    'the session is active again once the account is reactivated');

-- report_suspicious_session_use: 'possible'
SELECT is(
    report_suspicious_session_use('00000000-0000-4000-8000-000000009980', 9980, 'possible', '81.250.1.1', 'Edge')
        - 'alert_id',
    '{"known": true, "revoked": true}'::jsonb,
    'a possible attempt revokes the session'
);
SELECT isnt((SELECT revoked_at FROM sessions WHERE id = '00000000-0000-4000-8000-000000009980'), NULL,
    'the session is revoked');
SELECT is((SELECT count(*)::INT FROM connection_logs
           WHERE session_id = '00000000-0000-4000-8000-000000009980' AND action_type = 'SUSPICIOUS_IP_CHANGE'), 1,
    'the attempt is logged as SUSPICIOUS_IP_CHANGE');
SELECT results_eq(
    $$SELECT level, ip_address, device_info, sent_at IS NULL, acknowledged_at IS NULL FROM session_security_alerts
      WHERE session_id = '00000000-0000-4000-8000-000000009980'$$,
    $$VALUES ('possible'::TEXT, '81.250.1.1'::INET, 'Edge'::TEXT, TRUE, TRUE)$$,
    'one alert is queued with the address and the browser of the attempt'
);
SELECT is(
    (report_suspicious_session_use('00000000-0000-4000-8000-000000009980', 9980, 'possible', '81.250.1.1', 'Edge')
        ->> 'alert_id'),
    NULL,
    'a replayed token queues no second alert'
);
SELECT is((SELECT count(*)::INT FROM connection_logs
           WHERE session_id = '00000000-0000-4000-8000-000000009980' AND action_type = 'SUSPICIOUS_IP_CHANGE'), 2,
    'but the replayed attempt is logged');
SELECT is((SELECT count(*)::INT FROM session_security_alerts WHERE session_id = '00000000-0000-4000-8000-000000009980'), 1,
    'one alert per session and level');

-- 'certain'
SELECT isnt(
    report_suspicious_session_use('00000000-0000-4000-8000-000000009981', 9980, 'certain', '81.250.1.2', 'Opera')
        ->> 'alert_id',
    NULL,
    'a certain attempt on a bound session queues an alert'
);
SELECT is((SELECT count(*)::INT FROM connection_logs
           WHERE session_id = '00000000-0000-4000-8000-000000009981' AND action_type = 'STOLEN_SESSION_ATTEMPT'), 1,
    'and is logged as STOLEN_SESSION_ATTEMPT');

-- 'ip_change'
SELECT is(
    report_suspicious_session_use('00000000-0000-4000-8000-000000009982', 9980, 'ip_change', '81.250.1.3', 'Safari'),
    '{"known": true, "revoked": false, "alert_id": null}'::jsonb,
    'a network change of the bound device revokes nothing and queues nothing'
);
SELECT is((SELECT host(ip_address) FROM sessions WHERE id = '00000000-0000-4000-8000-000000009982'), '81.250.1.3',
    'the session follows the new address');

-- Unknown session, bad level
SELECT is(
    report_suspicious_session_use('00000000-0000-4000-8000-000000009982', 9981, 'possible', '81.250.1.4', 'x')
        ->> 'known',
    'false',
    'the session of another user is not reported'
);
SELECT throws_ok(
    $$SELECT report_suspicious_session_use('00000000-0000-4000-8000-000000009982', 9980, 'maybe', NULL, NULL)$$,
    '22023', NULL, 'an unknown level is refused'
);

-- Privileges
SELECT ok(
    has_function_privilege('project_api', 'report_suspicious_session_use(uuid, integer, text, inet, text)', 'EXECUTE')
    AND has_function_privilege('project_api', 'session_state(uuid, integer)', 'EXECUTE')
    AND NOT has_function_privilege('public', 'session_state(uuid, integer)', 'EXECUTE'),
    'every API runs the session functions, PUBLIC does not'
);
SELECT ok(
    NOT has_table_privilege('project_api', 'session_security_alerts', 'SELECT')
    AND NOT has_table_privilege('project_api', 'connection_logs', 'SELECT')
    AND has_table_privilege('core_api', 'session_security_alerts', 'UPDATE')
    AND has_table_privilege('core_api', 'connection_logs', 'SELECT'),
    'only core_api reads the alerts and the session log'
);

SELECT * FROM finish();
ROLLBACK;
