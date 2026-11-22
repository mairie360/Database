-- Milestones of a project (MAIR-1086, epic MAIR-822): dated steps of the project plan, marked
-- reached by hand. Project_API writes them; a deleted milestone keeps its row (`deleted_at`, soft
-- delete) and is left out of the lists. Deleting the project removes its milestones.
--
-- created_by / updated_by: author of the creation and of the last write, set by Project_API. No
-- foreign key to users, like project_templates.created_by (mair-691-02): the API test harness
-- starts with TRUNCATE users ... CASCADE, which a foreign key would extend to this table. User ids
-- are never reused, so an id left by a hard delete matches nobody. updated_at is kept fresh by
-- repeatable/project/trg_project_milestones_updated_at.sql.
CREATE TABLE project_milestones (
    id         SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    title      VARCHAR(255) NOT NULL
        CONSTRAINT chk_project_milestones_title CHECK (char_length(btrim(title)) BETWEEN 1 AND 255),
    due_date   DATE NOT NULL,
    reached    BOOLEAN NOT NULL DEFAULT FALSE,
    created_by INT NULL,
    updated_by INT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL
);

-- The milestones of a project in date order, deleted ones left out. It also covers the foreign key
-- (tests/30 lint).
CREATE INDEX idx_project_milestones_project_due
    ON project_milestones (project_id, due_date, id) WHERE deleted_at IS NULL;
