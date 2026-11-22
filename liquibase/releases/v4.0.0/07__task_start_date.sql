-- Start date of a task (MAIR-1087, epic MAIR-822): with due_date it places the task on the
-- project's timeline. Same type as tasks.due_date (TIMESTAMP, rel-1.0.0), NULL when not planned.
-- A task never starts after it is due. New nullable column: every existing row is NULL, so the
-- check is validated at once.
ALTER TABLE tasks
    ADD COLUMN IF NOT EXISTS start_date TIMESTAMP NULL
        CONSTRAINT chk_tasks_start_before_due
            CHECK (start_date IS NULL OR due_date IS NULL OR start_date <= due_date);
