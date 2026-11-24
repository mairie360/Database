-- Answer of an assigned member to an event invitation: `pending` until they answer, then
-- `accepted` or `declined`. Expand only: the column has a default, so the released Calendar_API
-- keeps inserting members without naming it.
ALTER TABLE event_members ADD COLUMN IF NOT EXISTS participation TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE event_members DROP CONSTRAINT IF EXISTS chk_event_members_participation;
ALTER TABLE event_members ADD CONSTRAINT chk_event_members_participation
    CHECK (participation IN ('pending', 'accepted', 'declined'));

-- The creator of an event who assigned themselves takes part in it.
UPDATE event_members em SET participation = 'accepted'
FROM events e
WHERE e.id = em.event_id AND e.created_by = em.user_id;
