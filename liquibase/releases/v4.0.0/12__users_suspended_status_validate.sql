-- MAIR-904: validates the CHECK added NOT VALID by mair-904-01, in its own transaction, so reads and
-- writes on users keep running during the scan.
ALTER TABLE users VALIDATE CONSTRAINT users_status_check;
