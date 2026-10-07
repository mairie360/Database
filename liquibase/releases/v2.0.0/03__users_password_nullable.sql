-- MAIR-141: an account that only signs in through the SSO has no local
-- password: users provisioned from Keycloak, and migrated users once their
-- local credential is retired. NULL now means "no local password" -- local
-- login is impossible for that row, only resolve_user_identity() can
-- authenticate it. chk_users_password_hashed (v1.3.0) keeps applying to
-- every non-NULL value: a CHECK passes on NULL, so a plaintext password is
-- still rejected.
ALTER TABLE users ALTER COLUMN password DROP NOT NULL;
