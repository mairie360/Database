-- MAIR-558: the priority of a project is the one chosen in the creation form, stored in
-- projects.priority (rel-1.2.0, default `medium`), which Project_API now reads and writes.
-- Until now nothing wrote that column and Project_API showed the highest priority of the
-- project's tasks instead: the existing projects keep the priority they were shown.
UPDATE projects p
SET priority = a.top_priority
FROM (
    SELECT project_id, max(priority) AS top_priority
    FROM tasks
    GROUP BY project_id
) a
WHERE a.project_id = p.id
  AND p.priority IS DISTINCT FROM a.top_priority;
