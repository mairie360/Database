-- Phone number split into country + national number (MAIR-480).
--
-- `users.phone_number` was a bare VARCHAR(15): no country, no format, so an
-- international number did not fit as E.164 (`+` and up to 15 digits) and a
-- consumer could not tell a French number from a foreign one. The phone is now
-- stored as two columns, set together or both NULL:
--   - `phone_country`: ISO 3166-1 alpha-2 code of the number's country (`FR`, `RE`...);
--   - `phone_number`:  national significant number, digits only, without the trunk
--                      prefix (`0612345678` in France is stored `612345678`).
-- E.164 is `+<calling code of phone_country><phone_number>`; Core API validates the
-- number against its country, this file only checks the shape.

ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_country CHAR(2);

-- Backfill. The APIs only accepted 10 to 15 digits so far: French national numbers
-- (`0XXXXXXXXX`, overseas departments by their prefix) and French numbers written with
-- their calling code without `+` (`33XXXXXXXXX`) are recognised. Anything else keeps its
-- digits with no country and is reported below.
UPDATE users SET
    phone_country = CASE
        WHEN phone_number ~ '^0(262|263|692|693)' THEN 'RE'
        WHEN phone_number ~ '^0(590|690|691)' THEN 'GP'
        WHEN phone_number ~ '^0(596|696|697)' THEN 'MQ'
        WHEN phone_number ~ '^0(594|694)' THEN 'GF'
        WHEN phone_number ~ '^0(269|639)' THEN 'YT'
        ELSE 'FR'
    END,
    phone_number = substr(phone_number, 2)
WHERE phone_country IS NULL AND phone_number ~ '^0[1-9][0-9]{8}$';

UPDATE users SET phone_country = 'FR', phone_number = substr(phone_number, 3)
WHERE phone_country IS NULL AND phone_number ~ '^33[1-9][0-9]{8}$';

-- An empty string meant "no phone" for some clients.
UPDATE users SET phone_number = NULL WHERE phone_country IS NULL AND phone_number = '';

ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_phone;
-- Written with COALESCE: a CHECK passes when it evaluates to NULL, so a bare
-- `phone_country ~ '...'` would let a number without a country through.
ALTER TABLE users ADD CONSTRAINT chk_users_phone CHECK (
    (phone_number IS NULL AND phone_country IS NULL)
    OR (COALESCE(phone_country ~ '^[A-Z]{2}$', FALSE)
        AND COALESCE(phone_number ~ '^[0-9]{4,15}$', FALSE))
) NOT VALID;

-- Validated when every row fits; otherwise the rows are listed and the constraint stays
-- NOT VALID (still enforced on every write), like chk_users_password_hashed in v1.6.0.
DO $$
DECLARE
    v_ids TEXT;
BEGIN
    SELECT string_agg(id::TEXT, ', ' ORDER BY id) INTO v_ids
    FROM users
    WHERE NOT ((phone_number IS NULL AND phone_country IS NULL)
        OR (COALESCE(phone_country ~ '^[A-Z]{2}$', FALSE)
            AND COALESCE(phone_number ~ '^[0-9]{4,15}$', FALSE)));
    IF v_ids IS NULL THEN
        ALTER TABLE users VALIDATE CONSTRAINT chk_users_phone;
    ELSE
        RAISE NOTICE 'chk_users_phone left NOT VALID: phone numbers without a known country on users %', v_ids;
    END IF;
END $$;

COMMENT ON COLUMN users.phone_country IS
    'ISO 3166-1 alpha-2 code of the phone number''s country; NULL when there is no phone (MAIR-480).';
COMMENT ON COLUMN users.phone_number IS
    'National significant number, digits only, without the trunk prefix; NULL when there is no phone (MAIR-480).';
