BEGIN;
SELECT plan(11);

-- MAIR-1231: function (job title) of an agent, edited on its Settings profile (releases/v4.1.0).
-- Plain text of 1 to 100 characters, copied into the audit log like the other identity columns,
-- cleared and pseudonymized at erasure, and watched by the compliance scan.

SELECT col_type_is('users', 'job_title', 'character varying(100)', 'users.job_title is a VARCHAR(100)');
SELECT col_is_null('users', 'job_title', 'users.job_title is optional');

INSERT INTO users (id, first_name, last_name, email, biography, job_title)
VALUES (9870, 'Jobqzxwv', 'Titlejkplm', 'job.title.qzxwv@example.com', 'Bio of Jobqzxwv', 'Chargée de mission voirie');

SELECT throws_ok(
    $$UPDATE users SET job_title = '   ' WHERE id = 9870$$, '23514', NULL,
    'a blank job title is refused');
SELECT throws_ok(
    $$UPDATE users SET job_title = E'\t\n ' WHERE id = 9870$$, '23514', NULL,
    'a job title made of tabs and line breaks only is refused');
SELECT throws_ok(
    format('UPDATE users SET job_title = %L WHERE id = 9870', repeat('a', 101)), '22001', NULL,
    'a job title over 100 characters is refused');
SELECT lives_ok(
    $$UPDATE users SET job_title = 'sha256:Jane Doe' WHERE id = 9870$$,
    'a job title may start like a digest');
SELECT lives_ok(
    $$UPDATE users SET job_title = 'Responsable du service voirie' WHERE id = 9870$$,
    'a job title of 1 to 100 characters is stored');

SELECT ok(
    EXISTS (SELECT 1 FROM users_audit_log WHERE user_id = 9870
            AND previous_data ->> 'job_title' = 'Chargée de mission voirie'),
    'the audit log keeps the previous job title, like the other identity columns');

SELECT anonymize_user(9870);

SELECT is((SELECT job_title FROM users WHERE id = 9870), NULL, 'anonymize_user() clears the job title');
SELECT is(
    (SELECT count(*)::int FROM users_audit_log WHERE user_id = 9870
     AND ((previous_data ->> 'job_title') !~ '^sha256:[0-9a-f]{64}$'
          OR (new_data ->> 'job_title') !~ '^sha256:[0-9a-f]{64}$')),
    0,
    'the job titles copied into the audit log are pseudonymized, one that only looked like a digest included');

-- A job title left on an anonymized account is reported by the compliance scan.
UPDATE users SET job_title = 'Left behind' WHERE id = 9870;
SELECT ok(
    EXISTS (SELECT 1 FROM fn_compliance_scan() WHERE kind = 'erased_user_data' AND location = 'users'),
    'the compliance scan reports a job title left on an anonymized account');

SELECT * FROM finish();
ROLLBACK;
