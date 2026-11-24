BEGIN;
SELECT plan(8);

-- mair_1176: the welcome tour state, a nullable boolean of user_preferences
-- (NULL = not done yet, no backfill).

SELECT has_column('user_preferences', 'onboarding_completed', 'mair_1176 user_preferences.onboarding_completed exists');
SELECT col_type_is('user_preferences', 'onboarding_completed', 'boolean', 'mair_1176 onboarding_completed is a boolean');
SELECT col_is_null('user_preferences', 'onboarding_completed', 'mair_1176 onboarding_completed is nullable (not done yet)');
SELECT col_hasnt_default('user_preferences', 'onboarding_completed', 'mair_1176 onboarding_completed has no default: a new row is not done');

INSERT INTO users (id, first_name, last_name, email, password) VALUES
    (9970, 'Onboarding', 'Agent', 'onboarding.agent@example.com', '$argon2id$v=19$m=16,t=2,p=1$c2FsdHNhbHQ$aGFzaGhhc2g');
SET CONSTRAINTS ALL IMMEDIATE;

-- Core creates the row with another preference, then marks the tour done and resets it, as core_api.
SET LOCAL ROLE core_api;
INSERT INTO user_preferences (user_id, theme) VALUES (9970, 'dark');
SELECT is((SELECT onboarding_completed FROM user_preferences WHERE user_id = 9970), NULL,
          'mair_1176 a preferences row created without it leaves the tour not done');
UPDATE user_preferences SET onboarding_completed = TRUE WHERE user_id = 9970;
RESET ROLE;
SELECT results_eq(
    $$SELECT onboarding_completed, theme::TEXT FROM user_preferences WHERE user_id = 9970$$,
    $$VALUES (TRUE, 'dark'::TEXT)$$,
    'mair_1176 core_api marks the tour done without touching the other preferences'
);

-- Erasure: the row goes with the account (the seeded administrator takes over its objects).
SELECT lives_ok('SELECT anonymize_user(9970)', 'mair_1176 the agent can be anonymized');
SELECT is_empty($$SELECT 1 FROM user_preferences WHERE user_id = 9970$$,
                'mair_1176 anonymize_user() deletes the tour state with the preferences row');

SELECT * FROM finish();
ROLLBACK;
