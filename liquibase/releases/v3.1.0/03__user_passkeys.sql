-- MAIR-505: passkeys (WebAuthn / FIDO2 credentials) of a Mairie 360 account.
--
-- Core_API is the WebAuthn relying party: one row per credential the user
-- registered (phone, security key, password manager...). `credential_id` is
-- the identifier the authenticator sends with every assertion and is unique
-- across the platform, which is how a login without an e-mail (discoverable
-- credential) finds the account. `passkey` holds the credential as serialised
-- by webauthn-rs: public key (COSE), signature counter, backup flags and the
-- attestation it was registered with. Core_API reads it back as a whole and
-- rewrites it after a successful authentication (counter, flags); nothing in
-- the schema interprets it beyond "a JSON object".
--
-- `user_identities` does not fit: a user has at most one identity per provider
-- there, and `subject` (255 characters) cannot hold a public key.
--
-- Passkeys survive archiving, like the SSO identities: Core_API refuses the
-- login of an archived account itself, and restore_user() brings the account
-- back with its credentials. Users are never hard-deleted, the ON DELETE
-- CASCADE only documents the ownership.
CREATE TABLE IF NOT EXISTS user_passkeys (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    credential_id BYTEA NOT NULL,
    passkey JSONB NOT NULL,
    label VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ,
    CONSTRAINT fk_user_passkeys_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT uq_user_passkeys_credential_id UNIQUE (credential_id),
    -- WebAuthn credential ids are 16 to 1023 bytes long.
    CONSTRAINT chk_user_passkeys_credential_id
        CHECK (octet_length(credential_id) BETWEEN 16 AND 1023),
    CONSTRAINT chk_user_passkeys_passkey CHECK (jsonb_typeof(passkey) = 'object'),
    CONSTRAINT chk_user_passkeys_label CHECK (btrim(label) <> '')
);

-- The list of a user's passkeys and the exclusion list of a new registration.
CREATE INDEX IF NOT EXISTS idx_user_passkeys_user_id ON user_passkeys (user_id);
