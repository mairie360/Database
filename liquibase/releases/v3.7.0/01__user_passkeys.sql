-- Passkeys (WebAuthn / FIDO2) of the accounts, managed by Core (MAIR-810).
--
-- user_passkeys: one row per registered passkey, several per user. `credential_id` is the credential
-- identifier given by the authenticator (unique: it is how a sign-in finds the account without an
-- e-mail). `passkey` is the serialized credential (public key and signature counter) kept by Core's
-- WebAuthn library, never returned by the API. `last_used_at` is set at each sign-in. The rows go with
-- the account (ON DELETE CASCADE, and anonymize_user()).
CREATE TABLE user_passkeys (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    credential_id BYTEA NOT NULL UNIQUE CHECK (octet_length(credential_id) > 0),
    passkey JSONB NOT NULL,
    label VARCHAR(100) NOT NULL CHECK (btrim(label) <> ''),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ
);
CREATE INDEX idx_user_passkeys_user_id ON user_passkeys (user_id);
