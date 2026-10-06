BEGIN;
SELECT plan(12);

-- MAIR-481 (releases/v1.12.0): events and recurrence rules stay inside
-- [1970-01-01, 3000-01-01) UTC. Postgres prints years outside 0001-9999 in a form
-- Calendar_API cannot parse back, so such a row made the API answer 500.

INSERT INTO users (id, first_name, last_name, email, password)
VALUES (480, 'Eva', 'Window', 'eva.window@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');

SELECT ok(
    (SELECT bool_and(convalidated) FROM pg_constraint
     WHERE conname IN ('chk_events_date_window', 'chk_recurrence_date_window')),
    'The date window constraints are validated'
);

-- events
SELECT lives_ok(
    $$INSERT INTO events (name, start_date, end_date, owner_id)
      VALUES ('Bounds', '1970-01-01 00:00:00+00', '2999-12-31 23:59:59.999999+00', 480)$$,
    'An event may span the whole window'
);
SELECT throws_ok(
    $$INSERT INTO events (name, start_date, end_date, owner_id)
      VALUES ('Too early', '1969-12-31 23:59:59+00', '1970-01-01 01:00:00+00', 480)$$,
    '23514', NULL,
    'An event starting before 1970 is refused'
);
SELECT throws_ok(
    $$INSERT INTO events (name, start_date, end_date, owner_id)
      VALUES ('BC', '4000-01-01 00:00:00+00 BC', '2026-01-01 00:00:00+00', 480)$$,
    '23514', NULL,
    'An event starting before Christ is refused'
);
SELECT throws_ok(
    $$INSERT INTO events (name, start_date, end_date, owner_id)
      VALUES ('Too late', '2026-10-05 18:00:00+00', '3000-01-01 00:00:00+00', 480)$$,
    '23514', NULL,
    'An event ending in year 3000 is refused'
);
SELECT throws_ok(
    $$INSERT INTO events (name, start_date, end_date, owner_id)
      VALUES ('Far', '2026-10-05 18:00:00+00', '200000-01-01 00:00:00+00', 480)$$,
    '23514', NULL,
    'An event ending in year 200000 is refused'
);
SELECT throws_ok(
    $$UPDATE events SET end_date = '3500-01-01 00:00:00+00' WHERE name = 'Bounds'$$,
    '23514', NULL,
    'An update moving an event out of the window is refused'
);

-- recurrence_rules
SELECT lives_ok(
    $$INSERT INTO recurrence_rules (type_recurrence, start_date, end_date, start_time, duration, owner_id)
      VALUES ('daily', '1970-01-01 00:00:00+00', '3000-01-01 00:00:00+00', '00:00', '01:00:00', 480)$$,
    'A rule may end on 3000-01-01 (day after its last occurrence, 2999-12-31)'
);
SELECT lives_ok(
    $$INSERT INTO recurrence_rules (type_recurrence, start_date, end_date, start_time, duration, owner_id)
      VALUES ('daily', '2026-10-05 18:00:00+00', NULL, '18:00', '01:00:00', 480)$$,
    'A rule that never ends is accepted'
);
SELECT throws_ok(
    $$INSERT INTO recurrence_rules (type_recurrence, start_date, end_date, start_time, duration, owner_id)
      VALUES ('daily', '2026-10-05 18:00:00+00', '3000-01-02 00:00:00+00', '18:00', '01:00:00', 480)$$,
    '23514', NULL,
    'A rule ending after 3000-01-01 is refused'
);
SELECT throws_ok(
    $$INSERT INTO recurrence_rules (type_recurrence, start_date, end_date, start_time, duration, owner_id)
      VALUES ('daily', '1969-12-31 00:00:00+00', '2027-01-01 00:00:00+00', '00:00', '01:00:00', 480)$$,
    '23514', NULL,
    'A rule starting before 1970 is refused'
);
SELECT throws_ok(
    $$INSERT INTO recurrence_rules (type_recurrence, start_date, end_date, start_time, duration, owner_id)
      VALUES ('daily', '3000-06-01 00:00:00+00', NULL, '00:00', '01:00:00', 480)$$,
    '23514', NULL,
    'A rule that never ends cannot start in year 3000'
);

SELECT * FROM finish();
ROLLBACK;
