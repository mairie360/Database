-- Role of a member in a project (MAIR-1088, epic MAIR-822): `manager` manages the project with its
-- owner, `contributor` works on its tasks, `reader` only reads it. Project_API decides what each
-- role may do. Existing members (and the writers of the release in prod, which do not send the
-- column) get the default `contributor`, the right of every member until now: an expand step.
CREATE TYPE project_member_role AS ENUM ('manager', 'contributor', 'reader');

ALTER TABLE project_members
    ADD COLUMN IF NOT EXISTS role project_member_role NOT NULL DEFAULT 'contributor';
