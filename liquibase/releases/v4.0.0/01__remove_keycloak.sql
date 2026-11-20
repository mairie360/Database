-- Core is the only account system: nothing signs in through Keycloak any more, so the objects that
-- served the SSO and its migration go away. Irreversible for the data: the links between accounts and
-- Keycloak subjects are dropped for good (the rollback only gives the empty table back).
--
-- users.password stays nullable: an account created by a former synchronisation may have no local
-- password yet; it sets one through the e-mailed link (forgot-password flow of Core).
-- compliance_storage keeps its 'keycloak' value (Postgres cannot drop an enum value, and the
-- append-only compliance_journal keeps the proof of the erasures that went through Keycloak).
DROP VIEW IF EXISTS v_users_sso_export;
DROP FUNCTION IF EXISTS link_user_identity(INT, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS resolve_user_identity(VARCHAR, VARCHAR);
DROP TABLE IF EXISTS user_identities;

-- No erasure step goes through Keycloak any more. The finished and pending rows of that step are
-- removed; the journal keeps the proof of the ones that ran.
DELETE FROM erasure_steps WHERE step = 'keycloak';
ALTER TABLE erasure_steps DROP CONSTRAINT IF EXISTS erasure_steps_step_check;
ALTER TABLE erasure_steps ADD CONSTRAINT erasure_steps_step_check
    CHECK (step IN ('resend', 's3', 'redis', 'backup_key', 'database'));
