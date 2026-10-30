-- Tables of the per-instance compliance service (MAIR-498, Compliance_API).
--
-- compliance_journal: what the service found and did (a row past its retention, data left on an
-- erased account, a value masked in the logs, an erasure step), never the value itself: the kind,
-- where (storage + location: service, logger, table.column, bucket prefix), when, the action, a
-- masked excerpt and a cause hint. It is the proof of erasure the mairie keeps (GDPR art. 28, 30):
-- append-only (fn_protect_compliance_journal), kept with the security logs.
--
-- erasure_steps: the erasure of a user propagated outside the database (Keycloak, Resend, S3,
-- Redis, the backup key of MAIR-500) and the database step itself, one row per user and step,
-- replayable: the service retries the pending and failed ones. `last_error` holds a short reason,
-- never a value of the user.
CREATE TYPE compliance_action AS ENUM ('detected', 'masked', 'erased', 'failed');
CREATE TYPE compliance_storage AS ENUM ('database', 'logs', 's3', 'redis', 'keycloak', 'resend', 'backup');

CREATE TABLE compliance_journal (
    id BIGSERIAL PRIMARY KEY,
    kind VARCHAR(64) NOT NULL CHECK (kind ~ '^[a-z][a-z0-9_]*$'),
    storage compliance_storage NOT NULL,
    location VARCHAR(255) NOT NULL,
    action compliance_action NOT NULL,
    rows BIGINT CHECK (rows IS NULL OR rows >= 0),
    masked_excerpt VARCHAR(1000),
    cause_hint VARCHAR(255),
    -- The erased account an erasure entry proves (no foreign key: the proof outlives everything).
    user_id INT,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_compliance_journal_detected_at ON compliance_journal (detected_at);
CREATE INDEX idx_compliance_journal_user_id ON compliance_journal (user_id) WHERE user_id IS NOT NULL;

CREATE TABLE erasure_steps (
    user_id INT NOT NULL REFERENCES users (id),
    step VARCHAR(16) NOT NULL CHECK (step IN ('keycloak', 'resend', 's3', 'redis', 'backup_key', 'database')),
    status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done', 'failed')),
    attempts INT NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    last_error VARCHAR(255),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, step)
);
CREATE INDEX idx_erasure_steps_status ON erasure_steps (status) WHERE status <> 'done';
