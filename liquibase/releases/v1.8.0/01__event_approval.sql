-- Event approval stored on the event itself (MAIR-392).
--
-- Until now the approval of an event only lived on `event_members.validation_status`,
-- duplicated on every member row and recomputed by Calendar_API on each member change:
-- removing the Responsable who refused, or never inviting one, validated the event.
-- The decision now has one home, `events`, with who took it and when.
-- `event_members.validation_status` is kept for compatibility but no longer read.

ALTER TABLE events ADD COLUMN IF NOT EXISTS approval_status event_validation_status
    NOT NULL DEFAULT 'pending';
ALTER TABLE events ADD COLUMN IF NOT EXISTS approval_decided_by INTEGER;
ALTER TABLE events ADD COLUMN IF NOT EXISTS approval_decided_at TIMESTAMPTZ;

ALTER TABLE events DROP CONSTRAINT IF EXISTS fk_events_approval_decided_by;
ALTER TABLE events ADD CONSTRAINT fk_events_approval_decided_by
    FOREIGN KEY (approval_decided_by) REFERENCES users(id) ON DELETE SET NULL;

-- A pending event carries no decision.
ALTER TABLE events DROP CONSTRAINT IF EXISTS chk_events_approval_decision;
ALTER TABLE events ADD CONSTRAINT chk_events_approval_decision CHECK (
    approval_status <> 'pending'
    OR (approval_decided_by IS NULL AND approval_decided_at IS NULL)
);

CREATE INDEX IF NOT EXISTS idx_events_approval_decided_by ON events (approval_decided_by);

-- Backfill from the member statuses (`refused` > `pending` > `validated`). An event without
-- members is pending when its creator only has the User or Guest roles, validated otherwise.
UPDATE events e SET approval_status = CASE
    WHEN EXISTS (SELECT 1 FROM event_members m
                 WHERE m.event_id = e.id AND m.validation_status = 'refused') THEN 'refused'
    WHEN EXISTS (SELECT 1 FROM event_members m
                 WHERE m.event_id = e.id AND m.validation_status = 'pending') THEN 'pending'
    WHEN EXISTS (SELECT 1 FROM event_members m WHERE m.event_id = e.id) THEN 'validated'
    WHEN EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
                 WHERE ur.user_id = e.created_by AND r.name IN ('User', 'Guest'))
         AND NOT EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
                 WHERE ur.user_id = e.created_by AND r.name IN ('Admin', 'Maire', 'Responsable'))
        THEN 'pending'
    ELSE 'validated'
END::event_validation_status;
