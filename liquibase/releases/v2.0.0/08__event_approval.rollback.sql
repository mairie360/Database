-- Rollback of 01__event_approval.sql (MAIR-392).
--
-- v_securable_events selects `events.*` and was recreated with the approval
-- columns by the forward migration: dropped and recreated without them.
-- The decision itself is lost; `event_members.validation_status` was kept up to
-- date by Calendar_API only before this release.
DROP VIEW IF EXISTS v_securable_events;

DROP INDEX IF EXISTS idx_events_approval_decided_by;
ALTER TABLE events
    DROP CONSTRAINT IF EXISTS chk_events_approval_decision,
    DROP CONSTRAINT IF EXISTS fk_events_approval_decided_by,
    DROP COLUMN IF EXISTS approval_decided_at,
    DROP COLUMN IF EXISTS approval_decided_by,
    DROP COLUMN IF EXISTS approval_status;

CREATE VIEW v_securable_events AS
SELECT
    u.*,
    (SELECT id FROM resources WHERE name = 'events') as resource_id
FROM events u;
GRANT SELECT ON v_securable_events TO calendar_api;
