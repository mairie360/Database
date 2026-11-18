-- Groups linked to a project: every current and future member of a linked group sees the project,
-- with the rights of a project member. Project_API checks the caller may link the group (one of
-- their groups, any group for Admin and Maire) and keeps one group per project for now; the table
-- allows several. Deleting the project or the group removes the link.
CREATE TABLE project_groups (
    project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    group_id   INT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    linked_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (project_id, group_id)
);

-- Visibility lookup goes from the caller's groups to the projects.
CREATE INDEX idx_project_groups_group_id ON project_groups (group_id);
