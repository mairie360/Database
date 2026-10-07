-- Compatibility of the legacy phone writers (MAIR-480, releases/v3.0.0).
--
-- Before v1.10.0 the phone was a bare `phone_number` (French national format, `0612345678`)
-- with no country. Writers that still send it that way (the test fixtures of
-- mairie360_api_lib, an API release older than the schema during a deploy) would be refused by
-- `chk_users_phone`: a French number written without its country is converted here with the
-- rules of the v1.10.0 backfill (overseas departments by their prefix, `33...` as `FR`).
-- Anything else written without a country is left to the constraint.
CREATE OR REPLACE FUNCTION fn_users_normalize_legacy_phone()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.phone_country IS NULL AND NEW.phone_number = '' THEN
        NEW.phone_number := NULL;
    ELSIF NEW.phone_country IS NULL AND NEW.phone_number ~ '^0[1-9][0-9]{8}$' THEN
        NEW.phone_country := CASE
            WHEN NEW.phone_number ~ '^0(262|263|692|693)' THEN 'RE'
            WHEN NEW.phone_number ~ '^0(590|690|691)' THEN 'GP'
            WHEN NEW.phone_number ~ '^0(596|696|697)' THEN 'MQ'
            WHEN NEW.phone_number ~ '^0(594|694)' THEN 'GF'
            WHEN NEW.phone_number ~ '^0(269|639)' THEN 'YT'
            ELSE 'FR'
        END;
        NEW.phone_number := substr(NEW.phone_number, 2);
    ELSIF NEW.phone_country IS NULL AND NEW.phone_number ~ '^33[1-9][0-9]{8}$' THEN
        NEW.phone_country := 'FR';
        NEW.phone_number := substr(NEW.phone_number, 3);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_normalize_legacy_phone ON users;
CREATE TRIGGER trg_users_normalize_legacy_phone
BEFORE INSERT OR UPDATE OF phone_number, phone_country ON users
FOR EACH ROW EXECUTE FUNCTION fn_users_normalize_legacy_phone();
