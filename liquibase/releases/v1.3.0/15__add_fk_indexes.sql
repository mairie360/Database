---
-- PERFORMANCES : Index sur les clés étrangères non indexées
--
-- Sans index sur une clé étrangère, PostgreSQL effectue des sequential scans
-- lors des suppressions / mises à jour des lignes référencées (vérification
-- ON DELETE / ON UPDATE) et lors des jointures sur ces colonnes.
-- Couvre les 26 FK signalées par tests/15_performance_indexes.sql.
---

-- access_control
CREATE INDEX IF NOT EXISTS idx_access_control_permission_id ON access_control (permission_id);
CREATE INDEX IF NOT EXISTS idx_access_control_resource_id   ON access_control (resource_id);

-- connection_logs
CREATE INDEX IF NOT EXISTS idx_connection_logs_user_id ON connection_logs (user_id);

-- e-learning
CREATE INDEX IF NOT EXISTS idx_course_attachments_module_id ON course_attachments (module_id);
CREATE INDEX IF NOT EXISTS idx_course_modules_course_id     ON course_modules (course_id);
CREATE INDEX IF NOT EXISTS idx_user_courses_course_id       ON user_courses (course_id);
CREATE INDEX IF NOT EXISTS idx_user_modules_module_id       ON user_modules (module_id);

-- calendrier : events
CREATE INDEX IF NOT EXISTS idx_events_created_by     ON events (created_by);
CREATE INDEX IF NOT EXISTS idx_events_owner_group_id ON events (owner_group_id);
CREATE INDEX IF NOT EXISTS idx_events_owner_id       ON events (owner_id);
CREATE INDEX IF NOT EXISTS idx_events_recurrence_id  ON events (recurrence_id);

-- calendrier : recurrence
CREATE INDEX IF NOT EXISTS idx_recurrence_members_group_id      ON recurrence_members (group_id);
CREATE INDEX IF NOT EXISTS idx_recurrence_members_recurrence_id ON recurrence_members (recurrence_id);
CREATE INDEX IF NOT EXISTS idx_recurrence_members_user_id       ON recurrence_members (user_id);
CREATE INDEX IF NOT EXISTS idx_recurrence_rules_owner_group_id  ON recurrence_rules (owner_group_id);
CREATE INDEX IF NOT EXISTS idx_recurrence_rules_owner_id        ON recurrence_rules (owner_id);

-- groupes
CREATE INDEX IF NOT EXISTS idx_group_members_user_id ON group_members (user_id);
CREATE INDEX IF NOT EXISTS idx_groups_owner_id       ON groups (owner_id);

-- messagerie
CREATE INDEX IF NOT EXISTS idx_messages_owner_id                ON messages (owner_id);
CREATE INDEX IF NOT EXISTS idx_unread_counters_conversation_id  ON unread_counters (conversation_id);

-- projets
CREATE INDEX IF NOT EXISTS idx_project_members_user_id ON project_members (user_id);
CREATE INDEX IF NOT EXISTS idx_projects_owner_id       ON projects (owner_id);
CREATE INDEX IF NOT EXISTS idx_task_history_changed_by ON task_history (changed_by);
CREATE INDEX IF NOT EXISTS idx_task_history_task_id    ON task_history (task_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to       ON tasks (assigned_to);
CREATE INDEX IF NOT EXISTS idx_tasks_project_id        ON tasks (project_id);
