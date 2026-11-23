BEGIN;
SELECT plan(13);

-- E-learning V2 (epic MAIR-827), releases/v4.0.0/16-19: origin of a course, last activity of an
-- enrolment, yearly training goal and reminders of a mandatory course.

INSERT INTO users (id, first_name, last_name, email, password) VALUES
    (6000, 'Lea', 'Learner', 'lea.learner@elearning-v2.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (6001, 'Ada', 'Admin', 'ada.admin@elearning-v2.test', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
INSERT INTO courses (id, title) VALUES (6000, 'Internal course');
INSERT INTO course_modules (id, course_id, title, sort_order) VALUES (6000, 6000, 'First', 1), (6001, 6000, 'Second', 2);

-- Tests 1-2: origin of a course (MAIR-1150).
SELECT is((SELECT source FROM courses WHERE id = 6000), 'internal', 'a course is the mairie''s own by default');
SELECT throws_ok(
    $$UPDATE courses SET source = 'external' WHERE id = 6000$$,
    '23514', NULL,
    'an unknown origin is refused'
);

-- Tests 3-5: the yearly training goal is a single row (MAIR-1144).
SELECT is((SELECT annual_goal_minutes FROM elearning_settings), 600, 'the yearly goal is 10 hours by default');
SELECT throws_ok(
    $$INSERT INTO elearning_settings (id, annual_goal_minutes) VALUES (2, 300)$$,
    '23514', NULL,
    'the settings hold a single row'
);
SELECT throws_ok(
    $$UPDATE elearning_settings SET annual_goal_minutes = 0$$,
    '23514', NULL,
    'a goal of zero minutes is refused'
);

-- Tests 6-7: every module completion is an activity of the agent (MAIR-1143).
INSERT INTO user_courses (user_id, course_id) VALUES (6000, 6000);
SELECT is((SELECT last_activity_at FROM user_courses WHERE user_id = 6000 AND course_id = 6000), NULL,
          'an enrolment without activity has no last activity');
INSERT INTO user_modules (user_id, module_id, is_completed, completed_at) VALUES (6000, 6000, TRUE, CURRENT_TIMESTAMP);
SELECT is((SELECT status::TEXT || ':' || (last_activity_at IS NOT NULL)::TEXT FROM user_courses WHERE user_id = 6000 AND course_id = 6000),
          'in_progress:true',
          'a completed module starts the course and dates the activity');
-- Test 8 (MAIR-817): the enrolment above was made without a start date (an administrator enrolling
-- the agent); the first completed module gives it one.
SELECT isnt((SELECT started_at FROM user_courses WHERE user_id = 6000 AND course_id = 6000), NULL,
            'the first activity dates the start of an enrolment made by an administrator');

-- Tests 9-10: a later write never moves the activity backwards, nor the start date.
UPDATE user_courses SET last_activity_at = '2999-01-01 00:00', started_at = '2020-01-01 00:00' WHERE user_id = 6000 AND course_id = 6000;
INSERT INTO user_modules (user_id, module_id, is_completed, completed_at) VALUES (6000, 6001, TRUE, CURRENT_TIMESTAMP);
SELECT is((SELECT last_activity_at FROM user_courses WHERE user_id = 6000 AND course_id = 6000),
          '2999-01-01 00:00'::TIMESTAMP,
          'the activity keeps the newest date');
SELECT is((SELECT started_at FROM user_courses WHERE user_id = 6000 AND course_id = 6000),
          '2020-01-01 00:00'::TIMESTAMP,
          'a later activity keeps the start date');

-- Tests 11-13: reminders of a course (MAIR-1150).
INSERT INTO course_reminders (course_id, user_id, sent_by) VALUES (6000, 6000, 6001);
SELECT is((SELECT count(*)::INT FROM course_reminders WHERE user_id = 6000 AND sent_by = 6001), 1, 'a reminder is recorded');
SELECT is((SELECT (anonymize_user(6000) ->> 'user_id')::INT), 6000, 'the agent is erased');
SELECT is((SELECT count(*)::INT FROM course_reminders WHERE user_id = 6000), 0, 'the erasure deletes the reminders of the agent');

SELECT * FROM finish();
ROLLBACK;
