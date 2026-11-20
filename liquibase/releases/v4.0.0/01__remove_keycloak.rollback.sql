-- Gives the structure back, not the links: they are gone. The functions and the view were repeatable
-- objects, they are not part of the changelog any more.
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
    CONSTRAINT uq_user_identities_user_provider UNIQUE (user_id, provider),
    CONSTRAINT chk_user_identities_provider
        CHECK (provider ~ '^[a-z0-9][a-z0-9_-]*$'),
    CONSTRAINT chk_user_identities_subject CHECK (btrim(subject) <> '')
);
ALTER TABLE erasure_steps DROP CONSTRAINT IF EXISTS erasure_steps_step_check;
ALTER TABLE erasure_steps ADD CONSTRAINT erasure_steps_step_check
    CHECK (step IN ('keycloak', 'resend', 's3', 'redis', 'backup_key', 'database'));
