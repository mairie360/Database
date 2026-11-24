ALTER TABLE event_members DROP CONSTRAINT IF EXISTS chk_event_members_participation;
ALTER TABLE event_members DROP COLUMN IF EXISTS participation;
