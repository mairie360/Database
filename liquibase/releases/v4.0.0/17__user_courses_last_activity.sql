-- Last activity of an agent on a course (MAIR-1143): the « Reprendre où vous en étiez » card of the
-- E-learning front shows the course the agent worked on last. Set by the progress trigger
-- (repeatable/elearning/fn_update_user_course_progress.sql) at every module completion; backfilled
-- with the latest date the enrolment already knows. Expand only: a nullable column.
ALTER TABLE user_courses ADD COLUMN last_activity_at TIMESTAMP;

UPDATE user_courses uc
   SET last_activity_at = GREATEST(
           uc.started_at,
           uc.completed_at,
           (SELECT max(um.completed_at)
              FROM user_modules um
              JOIN course_modules cm ON cm.id = um.module_id
             WHERE um.user_id = uc.user_id AND cm.course_id = uc.course_id))
 WHERE uc.last_activity_at IS NULL;

CREATE INDEX idx_user_courses_last_activity ON user_courses (user_id, last_activity_at DESC);
