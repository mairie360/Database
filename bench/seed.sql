-- Volume seed for the load test. Shape of a large town hall: a few tens of
-- thousands of agents, years of messages, events and access logs.
--   psql -v scale=1 -f bench/seed.sql     (scale=1 ≈ 20k users, 2M messages)
-- Bulk tables are loaded with session_replication_role = replica, which skips
-- user triggers and FK checks; what those triggers would have written
-- (group owner membership, unread counters, task history) is generated here.

\if :{?scale}
\else
  \set scale 1
\endif

\timing on
SET client_min_messages = warning;
SELECT setseed(0.42);

\set n_users        (20000 * :scale)
\set n_groups       (500 * :scale)
\set n_convs        (20000 * :scale)
\set n_messages     (2000000 * :scale)
\set n_events       (200000 * :scale)
\set n_projects     (2000 * :scale)
\set n_tasks        (100000 * :scale)
\set n_acl          (200000 * :scale)
\set n_sessions     (40000 * :scale)
\set n_access_logs  (2000000 * :scale)

BEGIN;
SET LOCAL session_replication_role = replica;

-- users: id 1 is the seeded admin
INSERT INTO users (first_name, last_name, email, password, status, is_archived, created_at)
SELECT 'First' || g, 'Last' || (g % (5000 * :scale)), 'user' || g || '@bench.invalid',
       '$argon2id$v=19$m=19456,t=2,p=1$c2FsdHNhbHQ$aGFzaGhhc2hoYXNoaGFzaA',
       (ARRAY['active','inactive','offline'])[1 + g % 3],
       g % 50 = 0, now() - (g % 1000) * interval '1 day'
FROM generate_series(2, :n_users) g;

INSERT INTO user_roles (user_id, role_id)
SELECT id, CASE WHEN id % 200 = 0 THEN 3 ELSE 4 END FROM users WHERE id > 1;

-- groups (services) and members, owner included
INSERT INTO groups (owner_id, name, description)
SELECT 2 + (g * 37) % (:n_users - 1), 'Service ' || g, 'Bench group ' || g
FROM generate_series(1, :n_groups) g;

INSERT INTO group_members (group_id, user_id)
SELECT id, owner_id FROM groups
UNION
SELECT 1 + (g % :n_groups), 2 + (g * 7919) % (:n_users - 1)
FROM generate_series(1, 40000 * :scale) g
ON CONFLICT DO NOTHING;

-- conversations: 80% direct (2 members), 20% group (members of the group)
INSERT INTO conversations (title, group_id, kind, created_by, created_at)
SELECT CASE WHEN g % 5 = 0 THEN 'Conv ' || g END,
       CASE WHEN g % 5 = 0 THEN 1 + (g % :n_groups) END,
       CASE WHEN g % 5 = 0 THEN 'group' ELSE 'direct' END,
       2 + (g * 31) % (:n_users - 1), now() - (g % 700) * interval '1 day'
FROM generate_series(1, :n_convs) g;

INSERT INTO conversation_members (conversation_id, user_id)
SELECT c.id, u FROM conversations c,
LATERAL (VALUES (c.created_by), (2 + (c.id * 7907) % (:n_users - 1))) v(u)
WHERE c.kind = 'direct'
UNION
SELECT c.id, gm.user_id FROM conversations c JOIN group_members gm ON gm.group_id = c.group_id
WHERE c.kind = 'group'
ON CONFLICT DO NOTHING;

-- messages: skewed towards a minority of busy conversations
INSERT INTO messages (id, conversation_id, owner_id, content, created_at)
SELECT g, conv, 2 + (g * 13) % (:n_users - 1),
       'Message ' || g || ' ' || repeat('lorem ipsum ', 1 + g % 10),
       now() - ((:n_messages - g) * interval '15 seconds')
FROM (SELECT g, 1 + (floor(power(random(), 3) * :n_convs))::int AS conv
      FROM generate_series(1, :n_messages) g) s;
SELECT setval(pg_get_serial_sequence('messages', 'id'), :n_messages);

-- each member has read up to a random point; counters follow
INSERT INTO conversation_read_cursors (user_id, conversation_id, last_read_message_id)
SELECT cm.user_id, cm.conversation_id, m.max_id - (random() * 20)::int
FROM conversation_members cm
JOIN (SELECT conversation_id, max(id) AS max_id FROM messages GROUP BY 1) m USING (conversation_id)
WHERE random() < 0.8;

INSERT INTO unread_counters (user_id, conversation_id, unread_count)
SELECT c.user_id, c.conversation_id, count(*)
FROM conversation_read_cursors c
JOIN messages m ON m.conversation_id = c.conversation_id AND m.id > c.last_read_message_id
               AND m.owner_id IS DISTINCT FROM c.user_id
GROUP BY 1, 2;

-- events over ±2 years, individual or group-owned
INSERT INTO events (name, start_date, end_date, created_by, visibility, owner_id, owner_group_id,
                    category, approval_status, approval_decided_by, approval_decided_at)
SELECT 'Event ' || g, d, d + interval '1 hour' * (1 + g % 4),
       2 + (g * 17) % (:n_users - 1),
       (ARRAY['private','public'])[1 + g % 2]::event_visibility,
       CASE WHEN g % 3 <> 0 THEN 2 + (g * 17) % (:n_users - 1) END,
       CASE WHEN g % 3 = 0 THEN 1 + g % :n_groups END,
       (ARRAY['meeting','activity','ceremony','other'])[1 + g % 4],
       CASE WHEN g % 4 = 0 THEN 'pending' ELSE 'validated' END::event_validation_status,
       CASE WHEN g % 4 <> 0 THEN 1 END, CASE WHEN g % 4 <> 0 THEN d - interval '1 day' END
FROM (SELECT g, now() - interval '2 years' + random() * interval '4 years' AS d
      FROM generate_series(1, :n_events) g) s;

INSERT INTO event_members (event_id, user_id, validation_status)
SELECT e.id, 2 + (e.id * k * 101) % (:n_users - 1), 'validated'
FROM events e, generate_series(1, 3) k
ON CONFLICT DO NOTHING;

-- projects, members, tasks, assignees, history
INSERT INTO projects (title, description, owner_id, responsible_id, created_at)
SELECT 'Project ' || g, 'Bench project', 2 + (g * 23) % (:n_users - 1),
       2 + (g * 29) % (:n_users - 1), now() - (g % 500) * interval '1 day'
FROM generate_series(1, :n_projects) g;

INSERT INTO project_members (project_id, user_id)
SELECT p.id, 2 + (p.id * k * 53) % (:n_users - 1) FROM projects p, generate_series(1, 10) k
ON CONFLICT DO NOTHING;

INSERT INTO tasks (project_id, title, status, priority, description, due_date, updated_by)
SELECT 1 + (floor(power(random(), 2) * :n_projects))::int, 'Task ' || g,
       (ARRAY['todo','in_progress','completed','review'])[1 + g % 4]::task_status,
       (ARRAY['low','medium','high'])[1 + g % 3]::task_priority,
       repeat('description ', g % 30), now() + (g % 90 - 30) * interval '1 day',
       2 + (g * 41) % (:n_users - 1)
FROM generate_series(1, :n_tasks) g;

INSERT INTO task_assignees (task_id, user_id)
SELECT t.id, pm.user_id FROM tasks t
JOIN LATERAL (SELECT user_id FROM project_members WHERE project_id = t.project_id
              ORDER BY user_id LIMIT 1 + t.id % 2) pm ON true
ON CONFLICT DO NOTHING;

INSERT INTO task_history (task_id, changed_by, action, old_status, new_status, changes, changed_at)
SELECT t.id, t.updated_by, a.action,
       CASE WHEN a.action = 'status_changed' THEN 'todo'::task_status END,
       CASE WHEN a.action = 'status_changed' THEN t.status END,
       CASE WHEN a.action = 'task_updated' THEN '{"title": {"from": "x", "to": "y"}}'::jsonb END,
       t.created_at + a.n * interval '1 hour'
FROM tasks t,
LATERAL (VALUES (0, 'task_created'), (1, 'task_updated'), (2, 'status_changed')) a(n, action);

-- ACL entries on events, half per user, half per group
INSERT INTO access_control (user_id, group_id, resource_id, resource_instance_id, permission_id)
SELECT CASE WHEN g % 2 = 0 THEN 2 + (g * 97) % (:n_users - 1) END,
       CASE WHEN g % 2 = 1 THEN 1 + g % :n_groups END,
       6, 1 + (g * 7) % :n_events, (ARRAY[31, 32, 33])[1 + g % 3]
FROM generate_series(1, :n_acl) g
ON CONFLICT DO NOTHING;

-- sessions (one active in two) and access logs over the last 3 months
INSERT INTO sessions (user_id, token_hash, device_info, created_at, expires_at, revoked_at)
SELECT 2 + g % (:n_users - 1), md5('token' || g), 'bench-agent',
       now() - (g % 30) * interval '1 day',
       now() + CASE WHEN g % 2 = 0 THEN interval '1 day' ELSE interval '-1 day' END,
       CASE WHEN g % 7 = 0 THEN now() - interval '1 hour' END
FROM generate_series(1, :n_sessions) g;

COMMIT;

-- access_logs is loaded outside replica mode so rows are routed to their
-- partition. In production the monthly partitions of past months exist
-- because fn_ensure_access_logs_partitions() ran back then: create them.
DO $$
DECLARE m DATE;
BEGIN
    FOR m IN SELECT generate_series(date_trunc('month', now()) - interval '3 months',
                                    date_trunc('month', now()) - interval '1 month', interval '1 month')
    LOOP
        EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF access_logs FOR VALUES FROM (%L) TO (%L)',
                       'access_logs_y' || to_char(m, 'YYYY') || 'm' || to_char(m, 'MM'),
                       m, m + interval '1 month');
    END LOOP;
END $$;
INSERT INTO access_logs (user_id, resource_name, instance_id, action, result, reason, timestamp)
SELECT 2 + g % (:n_users - 1), 'events', 1 + g % :n_events, 'read',
       CASE WHEN g % 10 = 0 THEN 'DENIED' ELSE 'GRANTED' END::access_result,
       'GROUP_ACL', now() - random() * interval '90 days'
FROM generate_series(1, :n_access_logs) g;

VACUUM ANALYZE;
SELECT relname, n_live_tup FROM pg_stat_user_tables WHERE n_live_tup > 1000 ORDER BY 2 DESC;
