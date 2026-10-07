-- Same definitions as the releases that created them (v1.0.0, v1.1.0, v1.5.0).
CREATE INDEX IF NOT EXISTS idx_sessions_token_lookup ON sessions (token_hash);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_id ON messages (conversation_id, id);
CREATE INDEX IF NOT EXISTS idx_task_history_task_id ON task_history (task_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_user ON user_roles (user_id);
CREATE INDEX IF NOT EXISTS idx_permissions_resource_id ON permissions (resource_id);
