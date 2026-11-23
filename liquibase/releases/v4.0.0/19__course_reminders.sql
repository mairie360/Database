-- Reminders of a mandatory course (MAIR-1150): an administrator reminds the agents late on a
-- mandatory course; the agent sees the latest reminder on the course in the E-learning front. One
-- row per reminder sent. `sent_by` is the administrator (SET NULL when the account is deleted, the
-- reminder stays for the agent). Expand only: a new table.
CREATE TABLE course_reminders (
    id SERIAL PRIMARY KEY,
    course_id INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sent_by INT REFERENCES users(id) ON DELETE SET NULL,
    sent_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_course_reminders_user_course ON course_reminders (user_id, course_id, sent_at DESC);
CREATE INDEX idx_course_reminders_course_id ON course_reminders (course_id);
CREATE INDEX idx_course_reminders_sent_by ON course_reminders (sent_by);
