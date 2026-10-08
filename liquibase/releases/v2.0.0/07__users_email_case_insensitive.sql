-- MAIR-413: e-mail addresses are unique regardless of case. The SSO
-- resolution of API_lib matches them case-insensitively, so two accounts
-- differing only by case would resolve to the same identity.
--
-- Accounts that already collide cannot be merged automatically: the migration
-- stops and lists them, an operator merges or renames them, then the
-- migration is run again. uq_users_email (exact match) is kept.
DO $$
DECLARE
    v_duplicates TEXT;
BEGIN
    SELECT string_agg(format('%s (ids %s)', lower_email, ids), ', ')
    INTO v_duplicates
    FROM (
        SELECT lower(email) AS lower_email, string_agg(id::TEXT, ', ' ORDER BY id) AS ids
        FROM users
        GROUP BY lower(email)
        HAVING count(*) > 1
    ) d;

    IF v_duplicates IS NOT NULL THEN
        RAISE EXCEPTION 'users.email values differ only by case: %', v_duplicates
            USING HINT = 'Merge or rename these accounts, then run the migration again.';
    END IF;
END;
$$;

CREATE UNIQUE INDEX uq_users_email_lower ON users (lower(email));
