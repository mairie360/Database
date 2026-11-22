-- Budget of a project (MAIR-1085, epic MAIR-822): the amount voted by the council and the amount
-- already committed, in cents (BIGINT, never a float). NULL = not filled in; an amount is never
-- negative. New nullable columns: every existing row is NULL, the checks are validated at once.
ALTER TABLE projects
    ADD COLUMN IF NOT EXISTS budget_voted BIGINT NULL
        CONSTRAINT chk_projects_budget_voted CHECK (budget_voted >= 0);
ALTER TABLE projects
    ADD COLUMN IF NOT EXISTS budget_committed BIGINT NULL
        CONSTRAINT chk_projects_budget_committed CHECK (budget_committed >= 0);
