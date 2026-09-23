-- MAIR-141: what the Keycloak migration job reads to provision accounts.
-- One row per user, archived ones included so the job can disable (never
-- delete) their Keycloak account: `enabled` mirrors the local soft-delete.
-- `roles` are the role names to carry over, `identities` the provider ->
-- subject links already recorded ({} for a user not yet migrated), which is
-- how a replay tells a new account from an existing one without creating
-- duplicates. `has_local_password` tells the job whether the account can
-- still sign in locally (FALSE once it is SSO-only).
CREATE OR REPLACE VIEW v_users_sso_export AS
SELECT
    u.id,
    u.email,
    u.first_name,
    u.last_name,
    NOT COALESCE(u.is_archived, FALSE) AS enabled,
    u.password IS NOT NULL AS has_local_password,
    COALESCE(
        (SELECT array_agg(r.name ORDER BY r.name)
         FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = u.id),
        '{}'::VARCHAR[]
    ) AS roles,
    COALESCE(
        (SELECT jsonb_object_agg(i.provider, i.subject)
         FROM user_identities i
         WHERE i.user_id = u.id),
        '{}'::JSONB
    ) AS identities
FROM users u;
