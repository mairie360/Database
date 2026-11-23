-- MAIR-817: an agent enrolled by an administrator gets a user_courses row without started_at
-- (status not_started). fn_update_user_course_progress() only set started_at when it inserted the
-- row, so the first completed module of such an agent left it NULL. The function now fills it on the
-- first activity; this backfills the enrolments already started: the earliest module completion of
-- the agent on the course, else the last activity, else the completion date.
UPDATE user_courses uc
SET started_at = COALESCE(first_module.completed_at, uc.last_activity_at, uc.completed_at)
FROM (
    SELECT uc2.user_id, uc2.course_id,
           (SELECT MIN(um.completed_at)
              FROM user_modules um
              JOIN course_modules cm ON cm.id = um.module_id
             WHERE um.user_id = uc2.user_id AND cm.course_id = uc2.course_id AND um.is_completed) AS completed_at
      FROM user_courses uc2
     WHERE uc2.started_at IS NULL AND uc2.status <> 'not_started'
) first_module
WHERE uc.user_id = first_module.user_id
  AND uc.course_id = first_module.course_id
  AND uc.started_at IS NULL;
