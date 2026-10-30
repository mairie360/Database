-- Back to the key of 03__init_roles.sql: several roles per user are allowed again. The rows
-- dropped by the migration are not restored.
ALTER TABLE user_roles DROP CONSTRAINT user_roles_pkey;
ALTER TABLE user_roles ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);
