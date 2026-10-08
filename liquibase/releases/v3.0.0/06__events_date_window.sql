-- Event dates bounded to [1970-01-01, 3000-01-01) UTC (MAIR-481).
--
-- Calendar_API accepted any date chrono could parse. Postgres refuses dates before
-- 4713 BC, and prints years outside 0001-9999 (`200000-01-01...`, `0001-01-01... BC`)
-- in a form the API cannot parse back: such an event made its own GET, and every
-- GET /calendar listing it, answer 500. The API now refuses those dates; this file
-- deletes the rows already stored (fuzzing pollution, nothing worth keeping) and makes
-- the database refuse them too.
--
-- Window: events and recurrence rules start on or after 1970-01-01 00:00 UTC and end
-- before 3000-01-01 00:00 UTC. A rule's end_date is the day after its last occurrence
-- at 00:00 UTC (`ends_on` 2999-12-31 -> 3000-01-01), so it may reach that bound.

-- The events outside the window, or repeating along a rule outside it. Their members,
-- message links (ON DELETE CASCADE) and group ACL entries (written by
-- trigger_set_group_accesses, no foreign key) go with them.
CREATE TEMP TABLE mair481_rules ON COMMIT DROP AS
    SELECT id FROM recurrence_rules
    WHERE start_date < TIMESTAMPTZ '1970-01-01 00:00:00+00'
       OR start_date >= TIMESTAMPTZ '3000-01-01 00:00:00+00'
       OR end_date > TIMESTAMPTZ '3000-01-01 00:00:00+00';

CREATE TEMP TABLE mair481_events ON COMMIT DROP AS
    SELECT id FROM events
    WHERE start_date < TIMESTAMPTZ '1970-01-01 00:00:00+00'
       OR end_date >= TIMESTAMPTZ '3000-01-01 00:00:00+00'
       OR recurrence_id IN (SELECT id FROM mair481_rules);

DO $$
DECLARE
    v_events TEXT;
    v_rules TEXT;
BEGIN
    SELECT string_agg(id::TEXT, ', ' ORDER BY id) INTO v_events FROM mair481_events;
    SELECT string_agg(id::TEXT, ', ' ORDER BY id) INTO v_rules FROM mair481_rules;
    IF v_events IS NOT NULL OR v_rules IS NOT NULL THEN
        RAISE NOTICE 'MAIR-481: deleting events [%] and recurrence rules [%] outside 1970-01-01 - 3000-01-01',
            COALESCE(v_events, ''), COALESCE(v_rules, '');
    END IF;
END $$;

DELETE FROM access_control
WHERE resource_id = (SELECT id FROM resources WHERE name = 'events')
  AND resource_instance_id IN (SELECT id FROM mair481_events);

-- Events first: deleting a rule first would set events.recurrence_id to NULL while
-- is_exception stays set, which chk_recurrence refuses.
DELETE FROM events WHERE id IN (SELECT id FROM mair481_events);
DELETE FROM recurrence_rules
WHERE id IN (SELECT id FROM mair481_rules)
  AND NOT EXISTS (SELECT 1 FROM events e WHERE e.recurrence_id = recurrence_rules.id);

-- With chk_dates (end_date > start_date), these bound both dates of each row.
ALTER TABLE events DROP CONSTRAINT IF EXISTS chk_events_date_window;
ALTER TABLE events ADD CONSTRAINT chk_events_date_window CHECK (
    start_date >= TIMESTAMPTZ '1970-01-01 00:00:00+00'
    AND end_date < TIMESTAMPTZ '3000-01-01 00:00:00+00'
);

-- end_date is NULL for a rule that never ends: start_date is bounded on its own.
ALTER TABLE recurrence_rules DROP CONSTRAINT IF EXISTS chk_recurrence_date_window;
ALTER TABLE recurrence_rules ADD CONSTRAINT chk_recurrence_date_window CHECK (
    start_date >= TIMESTAMPTZ '1970-01-01 00:00:00+00'
    AND start_date < TIMESTAMPTZ '3000-01-01 00:00:00+00'
    AND (end_date IS NULL OR end_date <= TIMESTAMPTZ '3000-01-01 00:00:00+00')
);
