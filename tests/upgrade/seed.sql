-- Data set loaded on the baseline schema (the release deployed in prod) before
-- HEAD is applied, see run.sh. It mimics a live instance: the template admin
-- account still in place, a password stored before hashing was enforced, an
-- archived admin, and rows in every module. Ids start at 100 so they never
-- collide with the seeds. tests/upgrade/*_test.sql check what HEAD did to it.
BEGIN;

-- Users. 105 has a plaintext password, as written before MAIR-169. When the
-- baseline already has chk_users_password_hashed, the constraint is dropped
-- and re-added NOT VALID exactly as releases/v1.3.0 left it, the way such
-- rows exist on an instance. It goes first: the deferred default-role trigger
-- forbids ALTER TABLE once other users are pending.
DO $$
DECLARE
    v_has_check BOOLEAN := EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_password_hashed');
BEGIN
    IF v_has_check THEN
        ALTER TABLE users DROP CONSTRAINT chk_users_password_hashed;
    END IF;
    INSERT INTO users (id, first_name, last_name, email, password, status, is_archived)
    VALUES (105, 'Eve', 'Legacy', 'eve@upgrade.example', 'plaintext-legacy', 'offline', FALSE);
    IF v_has_check THEN
        ALTER TABLE users ADD CONSTRAINT chk_users_password_hashed
            CHECK (password ~ '^\$argon2id\$v=\d+\$m=\d+,t=\d+,p=\d+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$')
            NOT VALID;
    END IF;
END;
$$;

INSERT INTO users (id, first_name, last_name, email, password, status, is_archived) VALUES
    (100, 'Alice', 'Owner', 'alice@upgrade.example', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active', FALSE),
    (101, 'Bob', 'Member', 'bob@upgrade.example', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active', FALSE),
    (102, 'Carol', 'Learner', 'carol@upgrade.example', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'offline', FALSE),
    (103, 'Dan', 'Admin', 'dan@upgrade.example', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active', FALSE);


INSERT INTO user_roles (user_id, role_id) VALUES (100, 4), (101, 4), (102, 4), (103, 1);
INSERT INTO user_preferences (user_id, theme, language) VALUES (100, 'dark', 'fr');

-- Sessions: one live, one expired.
INSERT INTO sessions (user_id, token_hash, created_at, expires_at) VALUES
    (100, 'hash-live', now(), now() + interval '1 day'),
    (101, 'hash-expired', now() - interval '90 days', now() - interval '60 days');

-- Groups (the owner is added as a member by trigger).
INSERT INTO groups (id, owner_id, name) VALUES (100, 100, 'Town council');
INSERT INTO group_members (group_id, user_id) VALUES (100, 101) ON CONFLICT DO NOTHING;

-- Access logs, one of them old enough to land in a dated partition.
INSERT INTO access_logs (user_id, resource_name, instance_id, action, result, reason, timestamp) VALUES
    (100, 'groups', 100, 'read', 'GRANTED', 'OWNERSHIP', now()),
    (101, 'groups', 100, 'delete', 'DENIED', 'NO_MATCH', now() - interval '40 days');

-- Projects and tasks.
INSERT INTO projects (id, title, status, owner_id, responsible_id, labels) VALUES
    (100, 'Road works', 'active', 100, 101, ARRAY['roads']);
INSERT INTO project_members (project_id, user_id) VALUES (100, 100), (100, 101);
-- 101 keeps its comments and history in custom_fields, as Project_API wrote
-- them before MAIR-393.
INSERT INTO tasks (id, project_id, title, status, assigned_to, custom_fields) VALUES
    (100, 100, 'Close the street', 'todo', 101, '{}'),
    (101, 100, 'Reopen the street', 'in_progress', NULL,
     '{"fields": [{"label": "Budget"}],
       "comments": [{"author": {"id": "user-100"}, "message": "Barriers ordered", "createdAt": "2026-09-01T08:00:00Z"}],
       "history": [{"author": {"id": "user-101"}, "action": "task_updated", "label": "Title changed", "createdAt": "2026-09-02T08:00:00Z"}]}');
INSERT INTO task_assignees (task_id, user_id) VALUES (100, 101);

-- Calendar.
INSERT INTO events (id, name, start_date, end_date, owner_id, visibility) VALUES
    (100, 'Council meeting', now() + interval '7 days', now() + interval '7 days 2 hours', 100, 'private');
INSERT INTO event_members (event_id, user_id, validation_status) VALUES (100, 101, 'pending');

-- Messaging: a group conversation and a direct one (unread counters are
-- maintained by trigger).
INSERT INTO conversations (id, title, group_id, kind) VALUES
    (100, 'Council', 100, 'group'),
    (101, NULL, NULL, 'direct');
INSERT INTO conversation_members (conversation_id, user_id) VALUES (101, 100), (101, 102);
INSERT INTO messages (conversation_id, owner_id, content) VALUES
    (100, 100, 'Meeting moved to Monday'),
    (101, 100, 'Hello Carol'),
    (101, 102, 'Hello Alice');

-- Chats written by Message_API before MAIR-478: kind = 'direct' whatever they
-- are, and a participant who left lost their row. 102 and 103 are two direct
-- chats of the same pair created by the BFF (`Direct <recipient>`); 101 left
-- 103. 102 left 104. 105 is a group chat. Only 102 is left in 106 and never
-- wrote: the other participant is unknown.
INSERT INTO conversations (id, title, group_id, kind) VALUES
    (102, 'Direct 101', NULL, 'direct'),
    (103, 'Direct 101', NULL, 'direct'),
    (104, 'Direct 102', NULL, 'direct'),
    (105, 'Road works team', NULL, 'direct'),
    (106, 'Direct 102', NULL, 'direct');
INSERT INTO conversation_members (conversation_id, user_id) VALUES
    (102, 100), (102, 101), (103, 100), (104, 101),
    (105, 100), (105, 101), (105, 102), (106, 102);
INSERT INTO messages (conversation_id, owner_id, content) VALUES
    (102, 101, 'Hi Alice'),
    (103, 101, 'Are you there?'),
    (104, 102, 'See you tomorrow');

-- E-learning.
INSERT INTO courses (id, title, instructor_user_id) VALUES (100, 'GDPR basics', 103);
INSERT INTO course_modules (id, course_id, title) VALUES (100, 100, 'Personal data');
INSERT INTO course_attachments (id, module_id, title, file_type, file_url) VALUES
    (100, 100, 'Slides', 'pdf', 'https://files.upgrade.example/slides.pdf');
INSERT INTO user_courses (user_id, course_id, status) VALUES (102, 100, 'in_progress');
INSERT INTO user_modules (user_id, module_id, is_completed) VALUES (102, 100, FALSE);

COMMIT;

-- Archived after the fact, through the same path as the APIs (MAIR-413: an
-- archived admin keeps its user_roles row).
UPDATE users SET is_archived = TRUE, status = 'archived' WHERE id = 103;
