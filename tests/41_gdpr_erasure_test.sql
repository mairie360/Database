BEGIN;
SELECT plan(19);

-- Erasure and export of a user's data (MAIR-289, epic MAIR-284): anonymize_user(),
-- fn_anonymize_archived_users() through the `users` retention policy, export_user_data().
-- The inventory is loaded into gdpr_test.inventory (tests/gdpr/inventory_to_sql.py).

-- A marker user with unique values, an administrator to hand its objects over to, a colleague.
INSERT INTO users (id, first_name, last_name, email, password, phone_number, phone_country, biography, photo)
VALUES (9800, 'Markerqzxwv', 'Tracerjkplm', 'gdpr.erasure.qzxwv@example.com',
        '$argon2id$v=19$m=16,t=2,p=1$c2FsdHNhbHQ$aGFzaGhhc2g', '612987654', 'FR',
        'Bio of Markerqzxwv', '\x89504e47'::bytea),
       (9801, 'Admin', 'Erasure', 'admin.erasure@example.com', NULL, NULL, NULL, NULL, NULL),
       (9802, 'Colleague', 'Erasure', 'colleague.erasure@example.com', NULL, NULL, NULL, NULL, NULL);
SET CONSTRAINTS ALL IMMEDIATE;
INSERT INTO user_roles (user_id, role_id) SELECT 9801, id FROM roles WHERE name = 'Admin';
UPDATE users SET first_name = 'Markerqzxwv' WHERE id = 9800; -- one more audit row

-- What the marker owns or belongs to.
INSERT INTO sessions (id, user_id, token_hash, device_info) VALUES
    ('7a1f0000-0000-4000-8000-000000009800', 9800, 'erasure-session', 'Firefox 140 on Linux');
-- connection_logs (security log, kept) copies the device: a user agent, never the identity.
INSERT INTO user_identities (user_id, provider, subject) VALUES (9800, 'keycloak', 'kc-gdpr-erasure-qzxwv');
INSERT INTO groups (id, name, owner_id) VALUES (9800, 'Group of the marker', 9800);
-- The owner becomes a member by trigger (fn_add_owner_to_group).
INSERT INTO group_members (group_id, user_id) VALUES (9800, 9802);
INSERT INTO projects (id, title, owner_id) VALUES (9800, 'Project of the marker', 9800);
INSERT INTO events (id, name, start_date, end_date, owner_id, visibility) VALUES
    (9800, 'Private appointment', now(), now() + interval '1 hour', 9800, 'private'),
    (9801, 'Public meeting', now(), now() + interval '1 hour', 9800, 'public');
INSERT INTO conversations (id, kind, direct_user_low, direct_user_high, created_by)
VALUES (9800, 'direct', 9800, 9802, 9800);
INSERT INTO conversation_members (conversation_id, user_id) VALUES (9800, 9800), (9800, 9802);
INSERT INTO messages (conversation_id, owner_id, content) VALUES (9800, 9800, 'Hello there'), (9800, 9802, 'Hi');
INSERT INTO user_courses (user_id, course_id, status)
SELECT 9800, id, 'completed' FROM courses ORDER BY id LIMIT 1;

---
--- 1. EXPORT (before the erasure)
---
CREATE TEMP TABLE export AS SELECT export_user_data(9800) AS doc;

-- Test 1: the identity is exported, the password is not.
SELECT ok(
    (SELECT doc -> 'user' ->> 'email' = 'gdpr.erasure.qzxwv@example.com' AND NOT (doc -> 'user' ? 'password') FROM export),
    'the export holds the identity, without the password hash'
);

-- Test 2: every identifier column of the inventory that holds a user id is a key of the export.
SELECT is_empty(
    $$SELECT i.table_name || '.' || i.column_name
        FROM gdpr_test.inventory i
        JOIN information_schema.columns c
          ON c.table_schema = 'public' AND c.table_name = i.table_name AND c.column_name = i.column_name
       WHERE i.category = 'identifier' AND i.column_name <> 'id'
         AND c.data_type IN ('integer', 'bigint')
         AND NOT ((SELECT doc -> 'data' FROM export) ? (i.table_name || '.' || i.column_name))$$,
    'the export covers every column of the inventory that references the user'
);

-- Test 3: the rows are there, credentials left out.
SELECT ok(
    (SELECT jsonb_array_length(doc -> 'data' -> 'sessions.user_id') = 1
            AND NOT (doc -> 'data' -> 'sessions.user_id' -> 0 ? 'token_hash')
            AND jsonb_array_length(doc -> 'data' -> 'messages.owner_id') = 1
            AND jsonb_array_length(doc -> 'data' -> 'users_audit_log.user_id') >= 2
       FROM export),
    'the export holds the sessions (without token hash), the messages and the audit rows'
);

---
--- 2. ERASURE
---
CREATE TEMP TABLE result AS SELECT anonymize_user(9800) AS r;

-- Test 4: the result tells what Core must do next.
SELECT ok(
    (SELECT is_admin((r ->> 'handed_over_to')::int) AND (r ->> 'deleted_private_events')::int = 1
            AND r -> 'revoked_sessions' ? '7a1f0000-0000-4000-8000-000000009800' FROM result),
    'anonymize_user() returns the administrator, the deleted events and the sessions to revoke'
);

-- Test 5: no value of the marker remains in any text or JSON column of the schema.
CREATE TEMP TABLE leftovers (table_name TEXT, column_name TEXT, rows BIGINT);
DO $$
DECLARE
    v_col RECORD;
    v_rows BIGINT;
BEGIN
    FOR v_col IN
        SELECT c.table_name, c.column_name
        FROM information_schema.columns c
        JOIN pg_class t ON t.relname = c.table_name AND t.relnamespace = 'public'::regnamespace
        WHERE c.table_schema = 'public' AND t.relkind IN ('r', 'p') AND NOT t.relispartition
          AND c.data_type IN ('text', 'character varying', 'character', 'jsonb', 'json', 'bytea')
          AND c.table_name NOT IN ('databasechangelog', 'databasechangeloglock')
    LOOP
        EXECUTE format(
            'SELECT count(*) FROM public.%I WHERE %I::text ~* $1', v_col.table_name, v_col.column_name)
        INTO v_rows USING 'markerqzxwv|tracerjkplm|gdpr\.erasure\.qzxwv|612987654|kc-gdpr-erasure-qzxwv|89504e47';
        IF v_rows > 0 THEN
            INSERT INTO leftovers VALUES (v_col.table_name, v_col.column_name, v_rows);
        END IF;
    END LOOP;
END;
$$;
SELECT is_empty('SELECT * FROM leftovers', 'no value of the anonymized user remains in a text, JSON or binary column');

-- Test 6: the users row stays, anonymized and archived.
SELECT results_eq(
    $$SELECT first_name::text, email::text, password IS NULL, phone_number IS NULL, is_archived FROM users WHERE id = 9800$$,
    $$VALUES ('Anonymized', 'anonymized-9800@anonymized.invalid', TRUE, TRUE, TRUE)$$,
    'the users row is kept without identity, archived'
);

-- Test 7: the audit rows are kept, their identity hashed.
SELECT ok(
    (SELECT bool_and(new_data ->> 'email' LIKE 'sha256:%') AND count(*) >= 3 FROM users_audit_log WHERE user_id = 9800),
    'the audit rows stay, with the identity replaced by a hash'
);

-- Tests 8-10: owned objects.
SELECT is((SELECT count(*) FROM events WHERE id = 9800), 0::bigint, 'the private event of the user is deleted');
SELECT is((SELECT owner_id FROM events WHERE id = 9801), (SELECT (r ->> 'handed_over_to')::int FROM result),
          'the public event is handed over to the administrator');
SELECT ok((SELECT owner_id = (SELECT (r ->> 'handed_over_to')::int FROM result) FROM groups WHERE id = 9800)
          AND (SELECT owner_id = (SELECT (r ->> 'handed_over_to')::int FROM result) FROM projects WHERE id = 9800),
          'the group and the project are handed over to the administrator');

-- Test 11: the direct conversation stays for the other participant, messages included.
SELECT ok(
    (SELECT count(*) = 2 FROM messages WHERE conversation_id = 9800)
    AND EXISTS (SELECT 1 FROM conversation_members WHERE conversation_id = 9800 AND user_id = 9802)
    AND NOT EXISTS (SELECT 1 FROM conversation_members WHERE user_id = 9800),
    'the direct conversation and its messages stay for the other participant'
);

-- Test 12: the rows marked erasure: delete are gone.
SELECT ok(
    NOT EXISTS (SELECT 1 FROM sessions WHERE user_id = 9800)
    AND NOT EXISTS (SELECT 1 FROM user_identities WHERE user_id = 9800)
    AND NOT EXISTS (SELECT 1 FROM group_members WHERE user_id = 9800)
    AND NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = 9800),
    'sessions, identities, memberships and roles of the user are deleted'
);

-- Test 13: the training record is kept.
SELECT ok(
    NOT EXISTS (SELECT 1 FROM courses) OR EXISTS (SELECT 1 FROM user_courses WHERE user_id = 9800),
    'the training record is kept'
);

-- Tests 14-16: idempotent, not restorable, the seeded administrator is protected.
SELECT is((SELECT anonymize_user(9800) ->> 'already_anonymized'), 'true', 'a second call does nothing');
SELECT throws_ok('SELECT restore_user(9800)', '23001', NULL, 'an anonymized account cannot be restored');
SELECT throws_ok('SELECT anonymize_user(1)', '23001', NULL, 'the seeded administrator cannot be anonymized');

---
--- 3. ARCHIVED ACCOUNTS: anonymized by the retention policy
---
INSERT INTO users (id, first_name, last_name, email, password)
VALUES (9803, 'Oldarchivedzz', 'Account', 'old.archived.zz@example.com', NULL),
       (9804, 'Recentarchivedzz', 'Account', 'recent.archived.zz@example.com', NULL);
DELETE FROM v_users_active WHERE id IN (9803, 9804);
-- Back-date the archiving of 9803 past the period (the audit log is append-only: the row is
-- rewritten under the pseudonymization flag, as the owner would).
ALTER TABLE users_audit_log DISABLE TRIGGER tr_immutable_audit;
UPDATE users_audit_log SET action_date = now() - interval '2 years' WHERE user_id = 9803 AND action_type = 'ARCHIVE';
ALTER TABLE users_audit_log ENABLE TRIGGER tr_immutable_audit;

-- Test 17: the policy is configuration (1 year by default).
SELECT is((SELECT retention_period FROM retention_policies WHERE table_name = 'users'), interval '1 year',
          'archived accounts are anonymized after 1 year by default, read from retention_policies');

-- Test 18: fn_apply_retention_policies() anonymizes the old archive only.
SELECT is(
    (SELECT affected FROM fn_apply_retention_policies() WHERE table_name = 'users'),
    1::bigint,
    'the retention run anonymizes the account archived for longer than the period'
);
SELECT ok(
    is_user_anonymized(9803) AND NOT is_user_anonymized(9804),
    'the recently archived account keeps its identity'
);

SELECT * FROM finish();
ROLLBACK;
