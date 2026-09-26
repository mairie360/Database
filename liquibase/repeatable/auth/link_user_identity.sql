-- MAIR-141: records that `p_user_id` is known to `p_provider` as
-- `p_subject`. Single write path for user_identities, built for the Keycloak
-- migration job to be replayed safely:
--   * a user already linked to the provider with the same subject is left
--     untouched (no duplicate, no spurious updated_at bump);
--   * a user already linked to the provider with another subject is
--     re-linked (the provider re-issued the account, e.g. a rebuilt realm);
--   * a subject already linked to ANOTHER user is refused (unique_violation):
--     an identity is never silently moved from one account to another.
-- Archived users can be linked: the job provisions them disabled in
-- Keycloak, and the link is already in place when restore_user() brings
-- the account back. Login is refused by resolve_user_identity() instead.
-- Returns the user_identities.id of the link.
CREATE OR REPLACE FUNCTION link_user_identity(
    p_user_id INT,
    p_provider VARCHAR,
    p_subject VARCHAR
)
RETURNS INT AS $$
DECLARE
    v_identity_id INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id) THEN
        RAISE EXCEPTION 'User % does not exist.', p_user_id
        USING ERRCODE = 'foreign_key_violation';
    END IF;

    BEGIN
        INSERT INTO user_identities (user_id, provider, subject)
        VALUES (p_user_id, p_provider, p_subject)
        ON CONFLICT (user_id, provider) DO UPDATE
            SET subject = EXCLUDED.subject,
                updated_at = now()
            WHERE user_identities.subject IS DISTINCT FROM EXCLUDED.subject
        RETURNING id INTO v_identity_id;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'Identity %/% is already linked to another user.', p_provider, p_subject
        USING ERRCODE = 'unique_violation';
    END;

    -- The DO UPDATE ... WHERE skipped the row: it already holds this link.
    IF v_identity_id IS NULL THEN
        SELECT id INTO v_identity_id
        FROM user_identities
        WHERE user_id = p_user_id AND provider = p_provider;
    END IF;

    RETURN v_identity_id;
END;
$$ LANGUAGE plpgsql;
