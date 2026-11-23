-- E-learning settings of the instance (MAIR-1144): a single row (`id = 1`, never inserted or
-- deleted by an API) holding the yearly training goal of an agent, in minutes, shown next to the
-- training time of the year (« objectif annuel : 10 h »). Expand only: a new table.
CREATE TABLE elearning_settings (
    id SMALLINT PRIMARY KEY DEFAULT 1,
    annual_goal_minutes INT NOT NULL DEFAULT 600,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_elearning_settings_single_row CHECK (id = 1),
    CONSTRAINT chk_elearning_settings_annual_goal CHECK (annual_goal_minutes BETWEEN 1 AND 52560)
);
INSERT INTO elearning_settings (id) VALUES (1);
