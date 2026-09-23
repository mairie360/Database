-- MAIR-141: the SSO login path. Maps the identity asserted by a provider
-- (the `sub` claim of a Keycloak token) back to the local account, and
-- returns NULL when the identity is unknown or the account is archived:
-- archived users keep their link (so restore_user() brings them back as
-- they were) but cannot sign in.
CREATE OR REPLACE FUNCTION resolve_user_identity(
    p_provider VARCHAR,
    p_subject VARCHAR
)
RETURNS INT AS $$
    SELECT u.id
    FROM user_identities i
    JOIN users u ON u.id = i.user_id
    WHERE i.provider = p_provider
      AND i.subject = p_subject
      AND NOT COALESCE(u.is_archived, FALSE);
$$ LANGUAGE sql STABLE;
