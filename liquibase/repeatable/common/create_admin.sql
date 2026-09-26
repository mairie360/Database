-- MAIR-170: admin_email / admin_password are optional Liquibase changelog
-- parameters (-Dadmin_email / -Dadmin_password), passed by the migration job
-- from the sealed secret (see Devops/Deploiment's liquibase job and
-- Devops/ansible playbooks/secrets.yml). admin_password is expected to
-- already be an argon2id PHC hash -- Postgres cannot compute one (see
-- releases/v1.3.0/01__hash_user_passwords.sql), so hashing the generated
-- plaintext password happens outside this repo, the same way the template
-- hash below was pre-computed.
--
-- Same absent-parameter detection as security/api_roles.sql: when a
-- parameter is not supplied, Liquibase leaves the placeholder as-is, and
-- this changeset falls back to the public template account (dev compose,
-- pgTAP tests, matches the pre-MAIR-170 behaviour exactly).
--
-- Each placeholder sits on its own line inside the $tag$ quote on purpose:
-- see security/api_roles.sql for why.
DO $$
DECLARE
    v_email    TEXT;
    v_password TEXT;
    v_unset    BOOLEAN;
    v_template_email    CONSTANT VARCHAR := 'template.email@gmail.com';
    v_template_password CONSTANT VARCHAR := '$argon2id$v=19$m=19456,t=2,p=1$/iKF9PbiDRDs4EKPjlIIhg$UKx9vfwwps250mEP/bYp63CXbEnQGULeUAhDq+az9Aw';
BEGIN
    v_email := btrim($email$
        ${admin_email}
    $email$, E' \t\r\n');
    v_password := btrim($pwd$
        ${admin_password}
    $pwd$, E' \t\r\n');

    -- Built by concatenation so Liquibase does not substitute it.
    v_unset := v_email IS NULL OR v_email = '' OR left(v_email, 2) = '$' || '{'
        OR v_password IS NULL OR v_password = '' OR left(v_password, 2) = '$' || '{';

    IF v_unset THEN
        -- No secret supplied: keep seeding the public template account.
        INSERT INTO users (first_name, last_name, email, password, status, is_archived)
        VALUES ('Admin', 'User', v_template_email, v_template_password, 'active', FALSE)
        ON CONFLICT (email) DO NOTHING;

        -- Instances created before MAIR-169 still hold the seed password in
        -- plaintext (grandfathered by the NOT VALID chk_users_password_hashed).
        -- v_template_password is the argon2id hash of that same value, so
        -- swap it in: the password does not change, only its storage.
        UPDATE users
        SET password = v_template_password
        WHERE id = 1
          AND email = v_template_email
          AND password = 'password_template';

        -- Any other plaintext row must not be updated here: the constraint
        -- is enforced again on UPDATE and would fail the whole migration.
        UPDATE users
        SET first_connect = FALSE
        WHERE id = 1
          AND first_connect IS DISTINCT FROM FALSE
          AND password LIKE '$argon2id$%';

        INSERT INTO user_roles (user_id, role_id)
        VALUES (1, 1)
        ON CONFLICT DO NOTHING;
    ELSIF NOT EXISTS (SELECT 1 FROM users WHERE id = 1) THEN
        -- Fresh instance: seed the real admin account, forced to change
        -- their password on first login.
        INSERT INTO users (first_name, last_name, email, password, status, is_archived, first_connect)
        VALUES ('Admin', 'User', v_email, v_password, 'active', FALSE, TRUE)
        ON CONFLICT (email) DO NOTHING;

        INSERT INTO user_roles (user_id, role_id)
        VALUES (1, 1)
        ON CONFLICT DO NOTHING;
    ELSE
        -- Existing instance: replace the seed account only while it still
        -- carries the template credentials. Once an operator has changed
        -- them (first connect, or a previous run of this changeset already
        -- applied the real credentials), later replays must leave it alone.
        UPDATE users
        SET email = v_email,
            password = v_password,
            first_connect = TRUE
        WHERE id = 1
          AND email = v_template_email
          AND password = v_template_password;
    END IF;
END;
$$;
