-- One-off purge of the passwords and photos copied into users_audit_log (MAIR-286, epic MAIR-284).
--
-- Until MAIR-286, fn_audit_and_mutate_user() copied the whole users row (to_jsonb(OLD) /
-- to_jsonb(NEW)) into users_audit_log on every write: the password hash, and the plaintext
-- password of the accounts created before MAIR-169 (migrate_legacy_password() rewrote them with an
-- UPDATE, whose previous_data kept the plaintext), plus the photo. The trigger now leaves out the
-- columns gdpr/inventory.yaml marks `audit_log: false`; this changeset removes the same keys from
-- the rows written before. Everything else in those rows is kept.
--
-- users_audit_log is append-only (tr_immutable_audit, fn_protect_audit_log.sql): the trigger is
-- disabled for this UPDATE only, in the same transaction, and enabled again before the commit.
-- On a new database the trigger does not exist yet (repeatable changesets run after the releases)
-- and there is nothing to purge.
--
-- Record for the mairies (processor's record, GDPR art. 30): the date of the purge on an instance
-- is DATABASECHANGELOG.DATEEXECUTED of changeset `mair-286-01`, and the NOTICE below, in the logs
-- of the Liquibase job, gives the number of rows purged. See gdpr/purges.md.
DO $$
DECLARE
    v_excluded CONSTANT TEXT[] := ARRAY['password', 'photo'];
    v_has_guard BOOLEAN := EXISTS (
        SELECT 1 FROM pg_trigger
         WHERE tgrelid = 'public.users_audit_log'::regclass AND tgname = 'tr_immutable_audit');
    v_rows BIGINT;
BEGIN
    IF v_has_guard THEN
        ALTER TABLE users_audit_log DISABLE TRIGGER tr_immutable_audit;
    END IF;

    UPDATE users_audit_log
       SET previous_data = previous_data - v_excluded,
           new_data = new_data - v_excluded
     WHERE previous_data ?| v_excluded OR new_data ?| v_excluded;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_has_guard THEN
        ALTER TABLE users_audit_log ENABLE TRIGGER tr_immutable_audit;
    END IF;

    RAISE NOTICE 'MAIR-286: password and photo removed from % row(s) of users_audit_log', v_rows;
END;
$$;
