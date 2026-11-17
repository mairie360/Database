BEGIN;
SELECT plan(9);

-- Reuse of a rotated refresh token: releases/v3.8.0/01. A session keeps the hash of the
-- token its last rotation replaced and the time of that rotation, so Core_API can detect a reuse.

INSERT INTO users (id, first_name, last_name, email, password)
VALUES (9980, 'Rotation', 'Marker', 'rotation.marker@example.com', NULL);

SELECT has_column('sessions', 'previous_token_hash', 'sessions keeps the previous refresh token hash');
SELECT col_type_is('sessions', 'rotated_at', 'timestamp with time zone', 'sessions keeps the rotation time');
SELECT has_index('sessions', 'idx_sessions_previous_token_hash', 'previous_token_hash', 'the previous hash is indexed');
SELECT ok(
    (SELECT pg_get_indexdef('idx_sessions_previous_token_hash'::regclass) LIKE '%WHERE (previous_token_hash IS NOT NULL)%'),
    'the index only holds rotated sessions'
);

INSERT INTO sessions (user_id, token_hash) VALUES (9980, 'mair695_r1');
SELECT is(
    (SELECT ROW(previous_token_hash, rotated_at)::TEXT FROM sessions WHERE token_hash = 'mair695_r1'),
    ROW(NULL::TEXT, NULL::TIMESTAMPTZ)::TEXT,
    'a session never rotated has no previous hash nor rotation time'
);

-- The rotation Core_API runs: the current hash becomes the previous one, in the same UPDATE.
UPDATE sessions SET previous_token_hash = token_hash, token_hash = 'mair695_r2', rotated_at = now()
WHERE token_hash = 'mair695_r1';
SELECT is(
    (SELECT previous_token_hash FROM sessions WHERE token_hash = 'mair695_r2'),
    'mair695_r1',
    'the rotation keeps the replaced hash'
);
SELECT is(
    (SELECT count(*)::INT FROM connection_logs l JOIN sessions s ON s.id = l.session_id
      WHERE s.token_hash = 'mair695_r2' AND l.action_type = 'REFRESH'),
    1,
    'the rotation is still logged once as a REFRESH'
);

-- core_api finds the session by its previous hash and revokes it (table privileges of api_grants).
SET LOCAL ROLE core_api;
SELECT is(
    (SELECT count(*)::INT FROM sessions WHERE previous_token_hash = 'mair695_r1'),
    1,
    'core_api finds a session by the previous hash'
);
SELECT lives_ok(
    $$UPDATE sessions SET revoked_at = now() WHERE previous_token_hash = 'mair695_r1'$$,
    'core_api revokes the session of a reused token'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
