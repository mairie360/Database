BEGIN;
SELECT plan(8);

-- Settings V2 (MAIR-823, releases/v4.0.0/10): auto-save, system updates and login alerts,
-- nullable booleans like the other preferences (NULL = application default).

SELECT has_column('user_preferences', 'autosave', 'user_preferences.autosave exists');
SELECT col_type_is('user_preferences', 'autosave', 'boolean', 'autosave is a boolean');
SELECT col_is_null('user_preferences', 'autosave', 'autosave is nullable (application default)');
SELECT has_column('user_notification_settings', 'system_updates', 'user_notification_settings.system_updates exists');
SELECT col_is_null('user_notification_settings', 'system_updates', 'system_updates is nullable');
SELECT has_column('user_notification_settings', 'login_alerts', 'user_notification_settings.login_alerts exists');
SELECT col_is_null('user_notification_settings', 'login_alerts', 'login_alerts is nullable');

-- Core writes them as core_api, through its existing grants on the two tables.
INSERT INTO users (id, first_name, last_name, email, password) VALUES
    (9960, 'Settings', 'Two', 'settings.v2@example.com', '$argon2id$v=19$m=16,t=2,p=1$c2FsdHNhbHQ$aGFzaGhhc2g');
SET LOCAL ROLE core_api;
INSERT INTO user_preferences (user_id, autosave) VALUES (9960, TRUE);
INSERT INTO user_notification_settings (user_id, system_updates, login_alerts) VALUES (9960, FALSE, TRUE);
RESET ROLE;
SELECT results_eq(
    $$SELECT p.autosave, n.system_updates, n.login_alerts
      FROM user_preferences p JOIN user_notification_settings n USING (user_id) WHERE user_id = 9960$$,
    $$VALUES (TRUE, FALSE, TRUE)$$,
    'core_api writes the three new preferences'
);

SELECT * FROM finish();
ROLLBACK;
