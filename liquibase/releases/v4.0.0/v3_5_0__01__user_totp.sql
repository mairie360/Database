-- Second factor of the accounts: TOTP authenticator app and backup codes, managed by Core (MAIR-805).
--
-- user_totp: one row per user. `secret_encrypted` is the TOTP secret sealed by Core (AES-GCM, the key
-- TOTP_ENCRYPTION_KEY lives outside the database): the database never sees it in clear. The row is
-- created pending by the enrolment (`confirmed_at` NULL) and the 2FA is active once the first code is
-- confirmed. `last_used_step` is the last accepted 30-second time step: a code of a step already used
-- is refused, so a code cannot be replayed within its window.
--
-- user_backup_codes: the 10 single-use codes given at confirmation, stored as Argon2 hashes only.
-- A code is spent by setting `used_at`; regenerating the codes deletes the old rows.
CREATE TABLE user_totp (
    user_id INT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    secret_encrypted BYTEA NOT NULL CHECK (octet_length(secret_encrypted) > 0),
    confirmed_at TIMESTAMPTZ,
    last_used_step BIGINT CHECK (last_used_step IS NULL OR last_used_step >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_backup_codes (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    code_hash VARCHAR(255) NOT NULL CHECK (btrim(code_hash) <> ''),
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_user_backup_codes_user_id ON user_backup_codes (user_id) WHERE used_at IS NULL;
