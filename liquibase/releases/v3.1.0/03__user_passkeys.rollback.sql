-- MAIR-505 rollback: the registered passkeys are lost, users fall back to
-- their password (or the SSO).
DROP TABLE IF EXISTS user_passkeys;
