-- Projets / tâches : valeurs propres au projet (saisies indépendamment des
-- tâches) et affectation multiple des tâches.
--
-- Sécurité prod : contraintes sur `projects` (table préexistante) posées en
-- NOT VALID — appliquées aux écritures futures, sans rescanner l'existant.

---
-- projects : responsable, priorité, échéance et étiquettes propres
---
ALTER TABLE projects ADD COLUMN IF NOT EXISTS responsible_id INTEGER;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS priority       task_priority NOT NULL DEFAULT 'medium';
ALTER TABLE projects ADD COLUMN IF NOT EXISTS due_date       DATE;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS labels         TEXT[] NOT NULL DEFAULT '{}';

ALTER TABLE projects DROP CONSTRAINT IF EXISTS fk_projects_responsible;
ALTER TABLE projects ADD CONSTRAINT fk_projects_responsible
    FOREIGN KEY (responsible_id) REFERENCES users(id) ON DELETE SET NULL NOT VALID;

-- Étiquettes : pas d'élément vide (le tri / la déduplication restent au BFF).
ALTER TABLE projects DROP CONSTRAINT IF EXISTS chk_projects_labels;
ALTER TABLE projects ADD CONSTRAINT chk_projects_labels
    CHECK (array_position(labels, NULL) IS NULL AND NOT ('' = ANY (labels))) NOT VALID;

CREATE INDEX IF NOT EXISTS idx_projects_responsible_id ON projects (responsible_id);

---
-- task_assignees : plusieurs personnes par tâche
---
-- `tasks.assigned_to` est conservé pendant la transition ; il sera retiré dans
-- une release ultérieure, une fois les consommateurs adaptés.
CREATE TABLE IF NOT EXISTS task_assignees (
    task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (task_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_task_assignees_user ON task_assignees (user_id, task_id);

-- Reprise des affectations uniques existantes.
INSERT INTO task_assignees (task_id, user_id)
SELECT id, assigned_to FROM tasks WHERE assigned_to IS NOT NULL
ON CONFLICT (task_id, user_id) DO NOTHING;
