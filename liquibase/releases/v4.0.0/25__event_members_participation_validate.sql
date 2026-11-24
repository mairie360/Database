-- MAIR-1122: validates the CHECK added NOT VALID by mair-1122-01, in its own transaction, so reads
-- and writes on event_members keep running during the scan.
ALTER TABLE event_members VALIDATE CONSTRAINT chk_event_members_participation;
