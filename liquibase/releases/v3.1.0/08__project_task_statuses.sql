-- MAIR-566: task statuses set per project, copied from a project template.
--
-- Every project owns an ordered list of task statuses (name, colour, position), each in one
-- of the three fixed categories of `task_status`: `todo`, `in_progress`, `completed`
-- (`review` is no longer used). A task points to a status of its own project
-- (tasks.status_id) and tasks.status keeps its category, kept in sync by the trigger of
-- repeatable/project/fn_apply_task_status.sql: the archiving of completed tasks, the
-- progress and the pending task lists still read tasks.status, whatever the names.
--
-- A project is created from a template (projects.template_id, the default template when
-- none is given): repeatable/project/fn_copy_template_statuses.sql copies its statuses into
-- the project, so editing a template never changes an existing project. Project and template
-- keep at least one status per category (repeatable/project/fn_check_status_categories.sql).

-- 1. Templates and their statuses.
CREATE TABLE IF NOT EXISTS project_templates (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    -- Custom fields copied into projects.custom_field_schema of a project created from it.
    custom_field_schema JSONB NOT NULL DEFAULT '[]',
    -- The template of a project created without one; it cannot be deleted.
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_project_templates_name CHECK (btrim(name) <> '')
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_project_templates_name ON project_templates (lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS uq_project_templates_default ON project_templates (is_default) WHERE is_default;

CREATE TABLE IF NOT EXISTS project_template_statuses (
    id SERIAL PRIMARY KEY,
    template_id INT NOT NULL REFERENCES project_templates(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    color VARCHAR(7) NOT NULL DEFAULT '#64748B',
    category task_status NOT NULL,
    position INT NOT NULL,
    CONSTRAINT chk_project_template_statuses_name CHECK (btrim(name) <> ''),
    CONSTRAINT chk_project_template_statuses_color CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
    CONSTRAINT chk_project_template_statuses_category CHECK (category <> 'review'),
    CONSTRAINT chk_project_template_statuses_position CHECK (position >= 0),
    -- Deferred: a reorder swaps positions within one transaction.
    CONSTRAINT uq_project_template_statuses_position UNIQUE (template_id, position)
        DEFERRABLE INITIALLY DEFERRED
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_project_template_statuses_name
    ON project_template_statuses (template_id, lower(name));

-- 2. Statuses of a project, copied from its template.
CREATE TABLE IF NOT EXISTS project_task_statuses (
    id SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    color VARCHAR(7) NOT NULL DEFAULT '#64748B',
    category task_status NOT NULL,
    position INT NOT NULL,
    CONSTRAINT chk_project_task_statuses_name CHECK (btrim(name) <> ''),
    CONSTRAINT chk_project_task_statuses_color CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
    CONSTRAINT chk_project_task_statuses_category CHECK (category <> 'review'),
    CONSTRAINT chk_project_task_statuses_position CHECK (position >= 0),
    CONSTRAINT uq_project_task_statuses_position UNIQUE (project_id, position)
        DEFERRABLE INITIALLY DEFERRED
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_project_task_statuses_name
    ON project_task_statuses (project_id, lower(name));

ALTER TABLE projects ADD COLUMN IF NOT EXISTS template_id INT
    REFERENCES project_templates(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_projects_template_id ON projects (template_id);

-- A status holding tasks cannot be deleted: Project_API moves them first.
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS status_id INT
    REFERENCES project_task_statuses(id) ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS idx_tasks_status_id ON tasks (status_id);

-- 3. Templates provided from the start.
INSERT INTO project_templates (name, description, is_default) VALUES
    ('Simple', 'À faire, en cours, terminé.', TRUE),
    ('Avec validation', 'Les tâches terminées attendent une validation.', FALSE),
    ('Marché public', 'Les étapes d''un marché public, de l''étude à la réception.', FALSE),
    ('Événement', 'La préparation d''un événement, jusqu''au bilan.', FALSE)
ON CONFLICT DO NOTHING;

INSERT INTO project_template_statuses (template_id, name, color, category, position)
SELECT t.id, s.name, s.color, s.category::task_status, s.position
FROM (VALUES
    ('Simple', 'À faire', '#64748B', 'todo', 0),
    ('Simple', 'En cours', '#2563EB', 'in_progress', 1),
    ('Simple', 'Terminé', '#16A34A', 'completed', 2),
    ('Avec validation', 'À faire', '#64748B', 'todo', 0),
    ('Avec validation', 'En cours', '#2563EB', 'in_progress', 1),
    ('Avec validation', 'À valider', '#D97706', 'in_progress', 2),
    ('Avec validation', 'Validé', '#16A34A', 'completed', 3),
    ('Marché public', 'Étude', '#64748B', 'todo', 0),
    ('Marché public', 'Appel d''offres', '#7C3AED', 'in_progress', 1),
    ('Marché public', 'Attribution', '#2563EB', 'in_progress', 2),
    ('Marché public', 'Exécution', '#D97706', 'in_progress', 3),
    ('Marché public', 'Réception', '#16A34A', 'completed', 4),
    ('Événement', 'Préparation', '#64748B', 'todo', 0),
    ('Événement', 'Communication', '#7C3AED', 'in_progress', 1),
    ('Événement', 'Jour J', '#D97706', 'in_progress', 2),
    ('Événement', 'Bilan', '#16A34A', 'completed', 3)
) AS s (template, name, color, category, position)
JOIN project_templates t ON t.name = s.template
WHERE NOT EXISTS (SELECT 1 FROM project_template_statuses e WHERE e.template_id = t.id);

-- 4. Existing projects: the default template, its statuses, and every task attached to the
-- first status of its category. `review` (never written by Project_API) becomes in progress.
UPDATE projects SET template_id = (SELECT id FROM project_templates WHERE is_default)
WHERE template_id IS NULL;

INSERT INTO project_task_statuses (project_id, name, color, category, position)
SELECT p.id, ts.name, ts.color, ts.category, ts.position
FROM projects p
JOIN project_template_statuses ts ON ts.template_id = (SELECT id FROM project_templates WHERE is_default)
WHERE NOT EXISTS (SELECT 1 FROM project_task_statuses s WHERE s.project_id = p.id);

UPDATE tasks SET status = 'in_progress' WHERE status = 'review';

UPDATE tasks t
SET status_id = (
    SELECT s.id FROM project_task_statuses s
    WHERE s.project_id = t.project_id AND s.category = t.status
    ORDER BY s.position, s.id
    LIMIT 1)
WHERE t.status_id IS NULL;

ALTER TABLE tasks ALTER COLUMN status_id SET NOT NULL;
