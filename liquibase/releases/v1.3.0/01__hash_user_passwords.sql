-- MAIR-169: users.password must hold only an argon2id hash from now on, never
-- a plaintext password. Security: prod already has accounts created before
-- this change with a plaintext value in this column, so the constraint is
-- added NOT VALID -- it applies to future INSERT/UPDATE without rescanning or
-- failing on that historical data. Those rows are migrated in place by
-- repeatable/users/migrate_legacy_password.sql (called from the login path
-- on a successful plaintext compare, and by a one-off admin script for
-- accounts that never reconnect); VALIDATE CONSTRAINT, once none remain, is a
-- later ops step.
--
-- The format matches the PHC string produced by the `argon2` Rust crate
-- (API_lib): $argon2id$v=<version>$m=<kib>,t=<iterations>,p=<parallelism>$<salt>$<hash>,
-- salt and hash base64-encoded without padding.
ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_password_hashed;
ALTER TABLE users ADD CONSTRAINT chk_users_password_hashed
    CHECK (password ~ '^\$argon2id\$v=\d+\$m=\d+,t=\d+,p=\d+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$')
    NOT VALID;
