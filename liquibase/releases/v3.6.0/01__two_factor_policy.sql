-- Two-factor policy of the instance (MAIR-808): one row, read and written by Core alone.
--
-- `required`: every account must have a second factor; an agent without one can only enrol after
-- the password (Core answers `2fa_setup_required`, no session). Off at first: the instance opts in.
-- `totp_allowed` / `passkey_allowed` / `backup_codes_allowed`: the modes the administrator accepts.
-- At least one real mode must stay allowed (backup codes alone are a recovery, not a factor). A mode
-- removed here is refused at the next login, and the agent who used it enrols another one.
-- Passkeys (MAIR-810) start disallowed: nothing can enrol one yet.
-- `updated_by` / `updated_at`: author and date of the last change. `updated_by` has no foreign key,
-- like `action_by` of the audit tables: the policy must survive whatever happens to the users table
-- (the test tooling truncates it with CASCADE) and the author is kept as history anyway.
--
-- two_factor_policy_audit_log: every change of the policy, append-only, written by a trigger so the
-- API cannot forget it. API roles have no privilege on it (SECURITY DEFINER trigger), like
-- users_audit_log.
CREATE TABLE two_factor_policy (
    id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    required BOOLEAN NOT NULL DEFAULT FALSE,
    totp_allowed BOOLEAN NOT NULL DEFAULT TRUE,
    passkey_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    backup_codes_allowed BOOLEAN NOT NULL DEFAULT TRUE,
    updated_by INT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_two_factor_policy_one_mode CHECK (totp_allowed OR passkey_allowed)
);
INSERT INTO two_factor_policy (id) VALUES (1);

CREATE TABLE two_factor_policy_audit_log (
    audit_id BIGSERIAL PRIMARY KEY,
    action_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    action_by INT,
    previous_data JSONB NOT NULL,
    new_data JSONB NOT NULL
);

CREATE OR REPLACE FUNCTION fn_audit_two_factor_policy() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO two_factor_policy_audit_log (action_by, previous_data, new_data)
    VALUES (NEW.updated_by, to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE TRIGGER tr_audit_two_factor_policy
    AFTER UPDATE ON two_factor_policy
    FOR EACH ROW EXECUTE FUNCTION fn_audit_two_factor_policy();

-- One row, always: no second row (id = 1), no deletion.
CREATE OR REPLACE FUNCTION fn_protect_two_factor_policy() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION '% is not allowed on two_factor_policy: update the single row', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_protect_two_factor_policy
    BEFORE DELETE ON two_factor_policy
    FOR EACH STATEMENT EXECUTE FUNCTION fn_protect_two_factor_policy();

CREATE OR REPLACE FUNCTION fn_protect_two_factor_audit() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'two_factor_policy_audit_log is append-only';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_immutable_two_factor_audit
    BEFORE UPDATE OR DELETE ON two_factor_policy_audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION fn_protect_two_factor_audit();
