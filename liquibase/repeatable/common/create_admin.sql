-- Seeds the admin account (users.id = 1).
--
-- MAIR-170: admin_email / admin_password are Liquibase changelog parameters
-- (-Dadmin_email / -Dadmin_password), passed by the migration job from the
-- sealed secret (see Devops/Deploiment's liquibase job and Devops/ansible
-- playbooks/secrets.yml). admin_password is expected to already be an
-- argon2id PHC hash -- Postgres cannot compute one (see
-- releases/v1.3.0/01__hash_user_passwords.sql), so hashing happens outside
-- this repo.
--
-- MAIR-413: the public template account (credentials readable in this public
-- repository) is only seeded when -Dallow_template_admin=true is passed
-- explicitly: dev compose, pgTAP tests, e2e instances. Without credentials
-- and without that flag the migration fails, unless id = 1 already holds an
-- account that is not the template one (an instance provisioned earlier).
--
-- Same absent-parameter detection as security/api_roles.sql: when a
-- parameter is not supplied, Liquibase leaves the placeholder as-is. Each
-- placeholder sits on its own line inside the $tag$ quote on purpose: see
-- security/api_roles.sql for why.

DROP FUNCTION IF EXISTS seed_admin_account(TEXT, TEXT, BOOLEAN);

-- Kept as a function so that tests can exercise every branch with literal
-- values. Only the migration user (owner) can run it.
CREATE FUNCTION seed_admin_account(
    p_email TEXT,
    p_password TEXT,
    p_allow_template BOOLEAN
) RETURNS VOID AS $$
DECLARE
    v_template_email    CONSTANT VARCHAR := 'admin@example.invalid';
    -- Address of the template account before MAIR-413.
    v_legacy_template_email CONSTANT VARCHAR := 'template.email@gmail.com';
    v_template_password CONSTANT VARCHAR := '$argon2id$v=19$m=19456,t=2,p=1$/iKF9PbiDRDs4EKPjlIIhg$UKx9vfwwps250mEP/bYp63CXbEnQGULeUAhDq+az9Aw';
    -- Plaintext seed of instances created before MAIR-169: the same password
    -- as v_template_password, unhashed.
    v_legacy_template_password CONSTANT VARCHAR := 'password_template';
    v_unset BOOLEAN;
    v_admin users%ROWTYPE;
    v_is_template BOOLEAN;
BEGIN
    v_unset := p_email IS NULL OR p_email = '' OR p_password IS NULL OR p_password = '';

    SELECT * INTO v_admin FROM users WHERE id = 1;
    v_is_template := FOUND
        AND COALESCE(v_admin.email IN (v_template_email, v_legacy_template_email), FALSE)
        AND COALESCE(v_admin.password IN (v_template_password, v_legacy_template_password), FALSE);

    IF NOT v_unset THEN
        IF v_admin.id IS NULL THEN
            -- Fresh instance: seed the real admin account, forced to change
            -- their password on first login.
            INSERT INTO users (first_name, last_name, email, password, status, is_archived, first_connect)
            VALUES ('Admin', 'User', p_email, p_password, 'active', FALSE, TRUE);
        ELSIF v_is_template THEN
            -- Replace the seed account only while it still carries the
            -- template credentials. Once an operator has changed them (first
            -- connect, or a previous run already applied the real
            -- credentials), later replays leave it alone.
            UPDATE users
            SET email = p_email,
                password = p_password,
                first_connect = TRUE
            WHERE id = 1;
        ELSE
            RETURN;
        END IF;
    ELSIF p_allow_template THEN
        IF v_admin.id IS NULL THEN
            INSERT INTO users (first_name, last_name, email, password, status, is_archived)
            VALUES ('Admin', 'User', v_template_email, v_template_password, 'active', FALSE)
            ON CONFLICT (email) DO NOTHING;
        ELSIF NOT v_is_template THEN
            -- A dev database whose admin was customized: leave it alone.
            RETURN;
        END IF;

        -- Instances created before MAIR-169 still hold the seed password in
        -- plaintext (grandfathered by chk_users_password_hashed), and the ones
        -- created before MAIR-413 the third-party address: hash the former
        -- (same password, only its storage changes), move the latter to the
        -- reserved .invalid domain.
        UPDATE users
        SET password = v_template_password
        WHERE id = 1
          AND password = v_legacy_template_password;

        UPDATE users
        SET email = v_template_email
        WHERE id = 1
          AND email = v_legacy_template_email;

        -- Any other plaintext row must not be updated here: the constraint
        -- is enforced again on UPDATE and would fail the whole migration.
        UPDATE users
        SET first_connect = FALSE
        WHERE id = 1
          AND first_connect IS DISTINCT FROM FALSE
          AND password LIKE '$argon2id$%';
    ELSIF v_admin.id IS NULL OR v_is_template THEN
        RAISE EXCEPTION 'admin_email and admin_password must be supplied to seed the admin account (users.id = 1)'
            USING HINT = 'Pass -Dadmin_email and -Dadmin_password (ADMIN_EMAIL / ADMIN_PASSWORD in the database secret), or -Dallow_template_admin=true on a dev, test or e2e database.';
    ELSE
        -- Already provisioned with its own credentials: nothing to do.
        RETURN;
    END IF;

    INSERT INTO user_roles (user_id, role_id)
    SELECT 1, 1
    WHERE EXISTS (SELECT 1 FROM users WHERE id = 1)
    ON CONFLICT DO NOTHING;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION seed_admin_account(TEXT, TEXT, BOOLEAN) FROM PUBLIC;

DO $$
DECLARE
    v_email    TEXT;
    v_password TEXT;
    v_allow    TEXT;
BEGIN
    v_email := btrim($email$
        ${admin_email}
    $email$, E' \t\r\n');
    v_password := btrim($pwd$
        ${admin_password}
    $pwd$, E' \t\r\n');
    v_allow := btrim($allow$
        ${allow_template_admin}
    $allow$, E' \t\r\n');

    -- Built by concatenation so Liquibase does not substitute it.
    IF left(v_email, 2) = '$' || '{' THEN v_email := NULL; END IF;
    IF left(v_password, 2) = '$' || '{' THEN v_password := NULL; END IF;

    PERFORM seed_admin_account(v_email, v_password, lower(v_allow) = 'true');
END;
$$;
