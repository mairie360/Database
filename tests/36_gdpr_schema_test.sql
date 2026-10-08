BEGIN;
SELECT plan(19);

-- GDPR compliance of the schema (MAIR-286, epic MAIR-284), checked against the decisions of
-- gdpr/inventory.yaml (MAIR-285). docker-compose-test.yml loads the inventory into
-- gdpr_test.inventory (tests/gdpr/inventory_to_sql.py) before pg_prove: these tests read the
-- inventory, they do not copy it.

-- Test 1: the inventory is loaded, and it excludes at least the password from the audit log.
SELECT ok(
    EXISTS (SELECT 1 FROM gdpr_test.inventory
            WHERE table_name = 'users' AND column_name = 'password' AND NOT audit_log),
    'gdpr_test.inventory is loaded and marks users.password audit_log: false'
);

---
--- 1. AUDIT LOG: the columns marked `audit_log: false` never reach users_audit_log
---

-- A user goes through every audited action, each excluded column changing on the way.
INSERT INTO users (id, first_name, last_name, email, password, photo)
VALUES (9700, 'Audit', 'Secret', 'audit.secret@test.com',
        '$argon2id$v=19$m=16,t=2,p=1$c2FsdHNhbHQ$aGFzaGhhc2g', '\x89504e47'::bytea);
UPDATE users SET password = '$argon2id$v=19$m=16,t=2,p=1$bmV3c2FsdA$bmV3aGFzaA',
                 photo = '\x47494638'::bytea, first_name = 'Audited'
 WHERE id = 9700;
DELETE FROM v_users_active WHERE id = 9700;
DO $$ BEGIN PERFORM restore_user(9700); END $$;

-- Test 2: the four actions were audited.
SELECT results_eq(
    $$SELECT action_type::TEXT FROM users_audit_log WHERE user_id = 9700 ORDER BY audit_id$$,
    $$VALUES ('CREATE'), ('UPDATE'), ('ARCHIVE'), ('RESTORE')$$,
    'the creation, update, archiving and restoration of a user are audited'
);

-- Test 3: no audit row of the whole table (the seeded accounts included) holds an excluded column.
SELECT is_empty(
    $$SELECT a.audit_id, i.column_name
        FROM users_audit_log a
        JOIN gdpr_test.inventory i ON i.table_name = 'users' AND NOT i.audit_log
       WHERE a.previous_data ? i.column_name OR a.new_data ? i.column_name$$,
    'users_audit_log holds no column marked audit_log: false (password, photo...)'
);

-- Test 4: the audit still records the other columns, the change included.
SELECT is(
    (SELECT previous_data->>'first_name' || ' -> ' || (new_data->>'first_name')
       FROM users_audit_log WHERE user_id = 9700 AND action_type = 'UPDATE'),
    'Audit -> Audited',
    'the audit log keeps the columns that are not excluded, before and after the change'
);

-- Test 5: every excluded column exists, so the exclusion is not a typo.
SELECT is_empty(
    $$SELECT i.column_name FROM gdpr_test.inventory i
       WHERE i.table_name = 'users' AND NOT i.audit_log
         AND NOT EXISTS (SELECT 1 FROM information_schema.columns c
                          WHERE c.table_schema = 'public' AND c.table_name = 'users'
                            AND c.column_name = i.column_name)$$,
    'every column marked audit_log: false is a column of users'
);

---
--- 2. FOREIGN KEYS TO users: ON DELETE matches the `erasure` of the inventory
---
-- `delete`: the row goes with the agent (CASCADE). `anonymize` / `keep`: the row stays, so the
-- key must not cascade (SET NULL, or RESTRICT / NO ACTION until the value is reassigned).
-- Partitions inherit the key of their parent and are checked through it.

CREATE TEMP VIEW user_fks AS
SELECT c.conrelid::regclass::TEXT AS table_name, a.attname::TEXT AS column_name,
       c.confdeltype AS on_delete, i.erasure
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
  LEFT JOIN gdpr_test.inventory i
    ON i.table_name = c.conrelid::regclass::TEXT AND i.column_name = a.attname
 WHERE c.contype = 'f' AND c.confrelid = 'public.users'::regclass
   AND c.connamespace = 'public'::regnamespace AND NOT t.relispartition;

-- Test 6: the schema has foreign keys to users (the view is not empty by mistake).
SELECT cmp_ok((SELECT count(*) FROM user_fks), '>=', 30::BIGINT,
              'the foreign keys to users are found');

-- Test 7: each one is classified in the inventory.
SELECT is_empty(
    $$SELECT table_name, column_name FROM user_fks WHERE erasure IS NULL$$,
    'every foreign key to users is a personal column of the inventory'
);

-- Test 8: `delete` cascades.
SELECT is_empty(
    $$SELECT table_name, column_name, on_delete FROM user_fks
       WHERE erasure = 'delete' AND on_delete <> 'c'$$,
    'a reference marked erasure: delete is ON DELETE CASCADE'
);

-- Test 9: `anonymize` and `keep` do not.
SELECT is_empty(
    $$SELECT table_name, column_name, erasure FROM user_fks
       WHERE erasure IN ('anonymize', 'keep') AND on_delete = 'c'$$,
    'a reference marked erasure: anonymize or keep is not ON DELETE CASCADE'
);

---
--- 3. COLUMN PRIVILEGES OF THE API ROLES
---

-- Test 10: only core_api (login, sessions) reads a `credentials` column.
SELECT is_empty(
    $$SELECT r.rolname, i.table_name, i.column_name
        FROM gdpr_test.inventory i
        JOIN pg_class t ON t.relname = i.table_name AND t.relnamespace = 'public'::regnamespace
       CROSS JOIN pg_roles r
       WHERE i.category = 'credentials'
         AND r.rolname IN ('project_api', 'calendar_api', 'message_api', 'elearning_api')
         AND has_column_privilege(r.rolname, t.oid, i.column_name, 'SELECT')$$,
    'no API role but core_api can read a credentials column (password, token hash)'
);

-- Tests 11-14: what each API role can read of users, pinned (security/api_grants.sql).
CREATE FUNCTION pg_temp.readable_user_columns(p_role TEXT) RETURNS SETOF TEXT AS $$
    SELECT a.attname::TEXT FROM pg_attribute a
     WHERE a.attrelid = 'public.users'::regclass AND a.attnum > 0 AND NOT a.attisdropped
       AND has_column_privilege(p_role, 'public.users'::regclass, a.attname, 'SELECT');
$$ LANGUAGE sql;

SELECT set_eq($$SELECT pg_temp.readable_user_columns('project_api')$$,
              ARRAY['id', 'first_name', 'last_name'],
              'project_api reads the id and the names of users, nothing else');
SELECT set_eq($$SELECT pg_temp.readable_user_columns('calendar_api')$$,
              ARRAY['id', 'is_archived'],
              'calendar_api reads the id and the archived flag of users, nothing else');
SELECT set_eq($$SELECT pg_temp.readable_user_columns('message_api')$$,
              ARRAY['id'],
              'message_api reads the id of users, nothing else');
SELECT set_eq($$SELECT pg_temp.readable_user_columns('elearning_api')$$,
              ARRAY['id', 'first_name', 'last_name', 'is_archived'],
              'elearning_api reads the id, the names and the archived flag of users, nothing else');

-- Tests 15-18: column_privs_are on the password hash, for every API role.
SELECT column_privs_are('public', 'users', 'password', 'core_api', ARRAY['INSERT', 'SELECT', 'UPDATE'],
                        'core_api reads and writes the password hash, and nothing more');
SELECT column_privs_are('public', 'users', 'password', 'project_api', ARRAY[]::TEXT[],
                        'project_api has no privilege on the password hash');
SELECT column_privs_are('public', 'users', 'password', 'message_api', ARRAY[]::TEXT[],
                        'message_api has no privilege on the password hash');
SELECT column_privs_are('public', 'sessions', 'token_hash', 'calendar_api', ARRAY[]::TEXT[],
                        'calendar_api has no privilege on the session token hashes');

---
--- 4. PASSWORDS: argon2id hashes only
---

-- Test 19: no account of the migrated database (seed included) holds anything but an argon2id hash.
SELECT is_empty(
    $$SELECT id FROM users WHERE password IS NOT NULL AND password !~ '^\$argon2id\$v=19\$'$$,
    'every password of users is an argon2id hash'
);

SELECT * FROM finish();
ROLLBACK;
