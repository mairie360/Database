BEGIN;
SELECT plan(9);

-- Event approval stored on `events` (MAIR-392).

INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (2700, 'Camille', 'Agent', 'camille.agent@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (2701, 'Paul', 'Responsable', 'paul.responsable@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');

SELECT has_column('events', 'approval_status', 'events.approval_status exists');
SELECT col_type_is('events', 'approval_status', 'event_validation_status',
    'events.approval_status is an event_validation_status');
SELECT has_column('events', 'approval_decided_by', 'events.approval_decided_by exists');
SELECT has_column('events', 'approval_decided_at', 'events.approval_decided_at exists');

INSERT INTO events (id, name, start_date, end_date, created_by, owner_id)
VALUES (2700, 'Réunion de service', '2026-11-02 09:00:00+00', '2026-11-02 10:00:00+00', 2700, 2700);

SELECT is(
    (SELECT approval_status::text FROM events WHERE id = 2700),
    'pending',
    'A new event is pending unless the API decides otherwise'
);

SELECT throws_ok(
    $$ UPDATE events SET approval_decided_by = 2701, approval_decided_at = now() WHERE id = 2700 $$,
    '23514',
    NULL,
    'chk_events_approval_decision forbids a decision on a pending event'
);

SELECT lives_ok(
    $$ UPDATE events SET approval_status = 'refused', approval_decided_by = 2701,
           approval_decided_at = now() WHERE id = 2700 $$,
    'A refused event records who refused it and when'
);

SELECT throws_ok(
    $$ UPDATE events SET approval_decided_by = 999999 WHERE id = 2700 $$,
    '23503',
    NULL,
    'approval_decided_by references users'
);

DELETE FROM users WHERE id = 2701;
SELECT ok(
    (SELECT approval_decided_by IS NULL AND approval_status = 'refused' FROM events WHERE id = 2700),
    'Deleting the decider keeps the decision and clears approval_decided_by'
);

SELECT * FROM finish();
ROLLBACK;
