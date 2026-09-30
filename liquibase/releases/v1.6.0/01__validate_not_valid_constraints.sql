-- MAIR-236: clean legacy rows, then VALIDATE every constraint left NOT VALID by
-- v1.2.0 and v1.3.0.
--
-- Each cleanup is the least destructive fix that makes the row satisfy the
-- constraint: a dangling reference or an out-of-range value is reset to
-- NULL / its default, no row is deleted. Cleanups run before the matching
-- VALIDATE CONSTRAINT, and reference cleanups run before the exclusivity ones.

---
-- projects
---
UPDATE projects SET responsible_id = NULL
WHERE responsible_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = projects.responsible_id);

UPDATE projects
SET labels = ARRAY(SELECT l FROM unnest(labels) AS l WHERE l IS NOT NULL AND l <> '')
WHERE array_position(labels, NULL) IS NOT NULL OR '' = ANY (labels);

ALTER TABLE projects VALIDATE CONSTRAINT fk_projects_responsible;
ALTER TABLE projects VALIDATE CONSTRAINT chk_projects_labels;

---
-- conversations
---
UPDATE conversations
SET kind = CASE WHEN group_id IS NOT NULL THEN 'group' ELSE 'direct' END
WHERE kind NOT IN ('direct', 'group');

ALTER TABLE conversations VALIDATE CONSTRAINT chk_conversations_kind;

---
-- events
---
UPDATE events SET service_group_id = NULL
WHERE service_group_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM groups g WHERE g.id = events.service_group_id);

UPDATE events SET category = 'other'
WHERE category NOT IN ('meeting', 'activity', 'ceremony', 'other');

-- A group wins over a free-text label.
UPDATE events SET service_label = NULL
WHERE service_group_id IS NOT NULL AND service_label IS NOT NULL;

ALTER TABLE events VALIDATE CONSTRAINT fk_events_service_group;
ALTER TABLE events VALIDATE CONSTRAINT chk_events_category;
ALTER TABLE events VALIDATE CONSTRAINT chk_events_service_exclusive;

---
-- recurrence_rules
---
UPDATE recurrence_rules SET days_of_week = NULL
WHERE days_of_week IS NOT NULL
  AND NOT (
      array_ndims(days_of_week) = 1
      AND cardinality(days_of_week) BETWEEN 1 AND 7
      AND array_position(days_of_week, NULL) IS NULL
      AND days_of_week <@ ARRAY[0, 1, 2, 3, 4, 5, 6]::smallint[]
  );

UPDATE recurrence_rules SET intervalle = 1 WHERE intervalle < 1;

ALTER TABLE recurrence_rules VALIDATE CONSTRAINT chk_recurrence_days_of_week;
ALTER TABLE recurrence_rules VALIDATE CONSTRAINT chk_recurrence_intervalle;

---
-- courses
---
UPDATE courses SET instructor_user_id = NULL
WHERE instructor_user_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = courses.instructor_user_id);

UPDATE courses SET instructor_group_id = NULL
WHERE instructor_group_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM groups g WHERE g.id = courses.instructor_group_id);

-- At most one instructor representation: user, then group, then free-text label.
UPDATE courses SET instructor_group_id = NULL, instructor_label = NULL
WHERE instructor_user_id IS NOT NULL
  AND num_nonnulls(instructor_user_id, instructor_group_id, instructor_label) > 1;

UPDATE courses SET instructor_label = NULL
WHERE instructor_group_id IS NOT NULL
  AND num_nonnulls(instructor_user_id, instructor_group_id, instructor_label) > 1;

UPDATE courses SET level = NULL
WHERE level IS NOT NULL AND level NOT IN ('beginner', 'intermediate', 'advanced');

ALTER TABLE courses VALIDATE CONSTRAINT fk_courses_instructor_user;
ALTER TABLE courses VALIDATE CONSTRAINT fk_courses_instructor_group;
ALTER TABLE courses VALIDATE CONSTRAINT chk_courses_instructor_exclusive;
ALTER TABLE courses VALIDATE CONSTRAINT chk_courses_level;

---
-- course_attachments
---
UPDATE course_attachments SET duration_seconds = NULL WHERE duration_seconds < 0;
UPDATE course_attachments SET sort_order = 1 WHERE sort_order < 1;

-- A file-based attachment without a URL cannot be repaired: it is re-typed
-- 'other', which does not require one, so the row is kept.
UPDATE course_attachments SET file_type = 'other'
WHERE file_type IN ('video', 'pdf', 'document', 'link', 'audio')
  AND (file_url IS NULL OR length(file_url) = 0);

ALTER TABLE course_attachments VALIDATE CONSTRAINT chk_course_attachments_duration;
ALTER TABLE course_attachments VALIDATE CONSTRAINT chk_course_attachments_sort_order;
ALTER TABLE course_attachments VALIDATE CONSTRAINT chk_course_attachments_file_url;

---
-- users.password
---
-- Plaintext rows cannot be hashed in SQL (argon2id happens outside Postgres,
-- see migrate_legacy_password), so this constraint is validated only once no
-- legacy row remains. Until then it keeps guarding future writes.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM users
        WHERE password IS NOT NULL
          AND NOT (password ~ '^\$argon2id\$v=\d+\$m=\d+,t=\d+,p=\d+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$')
    ) THEN
        RAISE NOTICE 'chk_users_password_hashed left NOT VALID: legacy plaintext passwords remain';
    ELSE
        ALTER TABLE users VALIDATE CONSTRAINT chk_users_password_hashed;
    END IF;
END $$;
