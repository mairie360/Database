-- Préférences d'affichage et de notification, une ligne (au plus) par
-- utilisateur. Une valeur NULL, ou l'absence de ligne, signifie
-- « utiliser le réglage par défaut de l'application ».

CREATE TABLE IF NOT EXISTS user_preferences (
    user_id                 INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    theme                   VARCHAR(16),
    font_family             VARCHAR(128),
    font_size               SMALLINT,
    density                 VARCHAR(32),
    language                VARCHAR(16),
    timezone                VARCHAR(64),
    date_format             VARCHAR(32),
    home_page               VARCHAR(128),
    auto_open_notifications BOOLEAN,

    CONSTRAINT chk_user_preferences_theme
        CHECK (theme IS NULL OR theme IN ('light', 'dark', 'system')),
    CONSTRAINT chk_user_preferences_font_size
        CHECK (font_size IS NULL OR font_size > 0)
);

CREATE TABLE IF NOT EXISTS user_notification_settings (
    user_id  INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    email    BOOLEAN,
    push     BOOLEAN,
    desktop  BOOLEAN,
    messages BOOLEAN,
    projects BOOLEAN,
    calendar BOOLEAN
);
