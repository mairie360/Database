-- MAIR-169: argon2id hash of the placeholder password "password_template"
-- (m=19456 KiB, t=2, p=1 -- the `argon2` crate's default Params, matching
-- API_lib). This seed account must have its password changed on first
-- deployment regardless of the hash underneath it.
INSERT INTO users (first_name, last_name, email, password, status, is_archived)
VALUES (
    'Admin',
    'User',
    'template.email@gmail.com',
    '$argon2id$v=19$m=19456,t=2,p=1$/iKF9PbiDRDs4EKPjlIIhg$UKx9vfwwps250mEP/bYp63CXbEnQGULeUAhDq+az9Aw',
    'active',
    FALSE
)
ON CONFLICT (email) DO NOTHING;

UPDATE users
SET first_connect = FALSE
WHERE id = 1;

INSERT INTO user_roles (user_id, role_id)
VALUES (1, 1)
