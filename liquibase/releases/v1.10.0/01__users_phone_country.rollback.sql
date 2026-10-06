-- Rollback of 01__users_phone_country.sql (MAIR-480).
--
-- Numbers of the French numbering plan (France and the overseas departments of the
-- backfill) get their trunk prefix back (`612345678` -> `0612345678`), the format the
-- APIs wrote before. Foreign numbers keep their national number: their country is lost
-- (the column cannot hold `+` and a 15-digit number), as before this release.
-- The compatibility trigger (repeatable/users/trigger_normalize_legacy_phone.sql) reads
-- phone_country: dropped with it, recreated by the next update.
DROP TRIGGER IF EXISTS trg_users_normalize_legacy_phone ON users;
DROP FUNCTION IF EXISTS fn_users_normalize_legacy_phone();
ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_phone;

UPDATE users SET phone_number = '0' || phone_number
WHERE phone_country IN ('FR', 'RE', 'GP', 'MQ', 'GF', 'YT') AND length(phone_number) < 15;

COMMENT ON COLUMN users.phone_number IS NULL;
ALTER TABLE users DROP COLUMN IF EXISTS phone_country;
