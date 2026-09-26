-- MAIR-141: external identities of a Mairie 360 account (SSO with Keycloak).
--
-- One row links a local user to the account an identity provider knows them
-- by: `provider` names the identity provider ('keycloak' for the platform
-- SSO) and `subject` is the stable identifier that provider issues for the
-- account (the `sub` claim of its tokens), never the e-mail, which can change
-- on either side.
--
-- Two uniqueness rules make the Keycloak migration replayable without
-- duplicates: a provider subject is linked to at most one user, and a user
-- has at most one identity per provider. link_user_identity() in
-- repeatable/auth/ is the sanctioned write path and relies on both.
--
-- Identities survive archiving: the account is refused at login by
-- resolve_user_identity() (archived users cannot sign in) and comes back
-- linked when restore_user() reactivates it. Users are never hard-deleted,
-- the ON DELETE CASCADE only documents the ownership.
CREATE TABLE IF NOT EXISTS user_identities (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    provider VARCHAR(64) NOT NULL,
    subject VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_user_identities_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT uq_user_identities_provider_subject UNIQUE (provider, subject),
    -- Also serves as the index on the user_id foreign key (leading column).
    CONSTRAINT uq_user_identities_user_provider UNIQUE (user_id, provider),
    CONSTRAINT chk_user_identities_provider
        CHECK (provider ~ '^[a-z0-9][a-z0-9_-]*$'),
    CONSTRAINT chk_user_identities_subject CHECK (btrim(subject) <> '')
);
