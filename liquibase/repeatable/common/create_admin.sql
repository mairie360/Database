INSERT INTO users (first_name, last_name, email, password, status, is_archived)
VALUES ('Admin', 'User', 'template.email@gmail.com', 'password_template', 'active', FALSE)
ON CONFLICT (email) DO NOTHING;

UPDATE users
SET first_connect = FALSE
WHERE id = 1;

INSERT INTO user_roles (user_id, role_id)
VALUES (1, 1)
