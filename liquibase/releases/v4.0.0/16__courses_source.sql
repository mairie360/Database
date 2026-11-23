-- Origin of a course (MAIR-1150): `internal` = created by the mairie, `platform` = provided with
-- Mairie360. The administration counts and filters the courses by it instead of by category.
-- Expand only: a defaulted column, every existing course is the mairie's own.
ALTER TABLE courses ADD COLUMN source VARCHAR(16) NOT NULL DEFAULT 'internal';
ALTER TABLE courses ADD CONSTRAINT chk_courses_source CHECK (source IN ('internal', 'platform'));
