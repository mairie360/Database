-- Rollback of 01__events_date_window.sql (MAIR-481): drops the constraints. The deleted
-- events and recurrence rules are not restored (they could not be read back anyway).
ALTER TABLE events DROP CONSTRAINT IF EXISTS chk_events_date_window;
ALTER TABLE recurrence_rules DROP CONSTRAINT IF EXISTS chk_recurrence_date_window;
