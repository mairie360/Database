-- Answer of an assigned member to an event invitation: `pending` until they answer, then
-- `accepted` or `declined`. Expand only: the column has a default, so the released Calendar_API
-- keeps inserting members without naming it. The CHECK is added NOT VALID (no scan under the
-- lock), the backfill and the validation run in their own changesets (mair-1122-02, -03).
ALTER TABLE event_members ADD COLUMN IF NOT EXISTS participation TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE event_members DROP CONSTRAINT IF EXISTS chk_event_members_participation;
ALTER TABLE event_members ADD CONSTRAINT chk_event_members_participation
    CHECK (participation IN ('pending', 'accepted', 'declined')) NOT VALID;
