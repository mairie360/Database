ALTER TABLE users
ADD COLUMN first_connect BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE users SET first_connect = FALSE WHERE id = 1;
