-- Comments of a project (MAIR-1089, epic MAIR-822): the discussion of the project itself, next to
-- the comments of its tasks (task_comments, MAIR-393), written by Project_API. Like a task comment,
-- a project comment stays when its author is erased (anonymize_user() keeps the reference to the
-- anonymized account; a hard delete of the user sets it to NULL) and goes with its project.
CREATE TABLE project_comments (
    id         SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    author_id  INT NULL REFERENCES users(id) ON DELETE SET NULL,
    message    TEXT NOT NULL
        CONSTRAINT chk_project_comments_message CHECK (char_length(message) BETWEEN 1 AND 2000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Newest first, paginated per project (also covers the project foreign key).
CREATE INDEX idx_project_comments_project_created
    ON project_comments (project_id, created_at DESC, id DESC);
-- Every foreign key has an index (tests/30 lint): export and erasure look the author up.
CREATE INDEX idx_project_comments_author ON project_comments (author_id);
