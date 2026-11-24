BEGIN;
SELECT plan(6);

-- Answer of a member to an event invitation (MAIR-1122), releases/v4.0.0/23.

INSERT INTO users (id, first_name, last_name, email, password) VALUES
    (6401, 'Ana', 'Creator', 'ana.creator64@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g'),
    (6402, 'Ben', 'Guest', 'ben.guest64@mairie.fr', '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g');
INSERT INTO events (id, name, start_date, end_date, created_by, owner_id)
VALUES (6401, 'Weekly meeting', '2026-06-01 10:00:00+00', '2026-06-01 11:00:00+00', 6401, 6401);

-- Tests 1-2: the column exists, a member inserted without it is pending.
SELECT has_column('event_members', 'participation', 'event_members has a participation column');
INSERT INTO event_members (event_id, user_id) VALUES (6401, 6402);
SELECT is(
    (SELECT participation FROM event_members WHERE event_id = 6401 AND user_id = 6402),
    'pending',
    'a member assigned without an answer is pending'
);

-- Tests 3-4: accepted and declined are stored.
UPDATE event_members SET participation = 'accepted' WHERE event_id = 6401 AND user_id = 6402;
SELECT is(
    (SELECT participation FROM event_members WHERE event_id = 6401 AND user_id = 6402),
    'accepted',
    'a member can accept'
);
SELECT lives_ok(
    $$UPDATE event_members SET participation = 'declined' WHERE event_id = 6401 AND user_id = 6402$$,
    'a member can decline'
);

-- Tests 5-6: any other value or NULL is refused.
SELECT throws_ok(
    $$UPDATE event_members SET participation = 'maybe' WHERE event_id = 6401 AND user_id = 6402$$,
    '23514', NULL,
    'an unknown participation is refused'
);
SELECT throws_ok(
    $$UPDATE event_members SET participation = NULL WHERE event_id = 6401 AND user_id = 6402$$,
    '23502', NULL,
    'the participation cannot be NULL'
);

SELECT * FROM finish();
ROLLBACK;
