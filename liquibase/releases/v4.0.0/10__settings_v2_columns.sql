-- Settings V2 (MAIR-823): three preferences the Settings front offers and Core stores.
-- Nullable like the other preference columns: NULL means "application default".
--   user_preferences.autosave: drafts are saved automatically every 30 seconds (Général tab).
--   user_notification_settings.system_updates: notification type "Mises à jour système".
--   user_notification_settings.login_alerts: e-mail sent to the account at every new sign-in (Sécurité tab).
ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS autosave BOOLEAN;
ALTER TABLE user_notification_settings ADD COLUMN IF NOT EXISTS system_updates BOOLEAN;
ALTER TABLE user_notification_settings ADD COLUMN IF NOT EXISTS login_alerts BOOLEAN;
