-- MAIR-477: indexes the schema lint (tests/30_schema_lint_test.sql, MAIR-476) reports as
-- redundant. Each one is the same as, or a prefix of, a wider index that already serves the same
-- lookups and covers the same foreign key, so dropping it only saves writes and space.
DROP INDEX IF EXISTS idx_sessions_token_lookup;       -- = sessions_token_hash_key
DROP INDEX IF EXISTS idx_messages_conversation_id_id; -- = uq_messages_conversation_id_id
DROP INDEX IF EXISTS idx_task_history_task_id;        -- prefix of idx_task_history_task_changed
DROP INDEX IF EXISTS idx_user_roles_user;             -- prefix of user_roles_pkey
DROP INDEX IF EXISTS idx_permissions_resource_id;     -- prefix of uq_resource_action
