-- 1. Enums alignés (Tout en anglais pour correspondre au reste de ton code)
CREATE TYPE event_status AS ENUM ('pending', 'validated', 'refused');
CREATE TYPE recurrence_type AS ENUM ('daily', 'weekly', 'monthly');

-- 2. Table Récurrence (F33) [cite: 20]
CREATE TABLE recurrence_rules (
    id SERIAL PRIMARY KEY,
    type_recurrence recurrence_type NOT NULL,
    intervalle INT DEFAULT 1,
    date_fin TIMESTAMP DEFAULT NULL
);

-- 3. Table Événements [cite: 20]
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    start_date TIMESTAMP NOT NULL,
    end_date TIMESTAMP NOT NULL,

    -- Cycle de validation aligné sur l'enum (F27, F30) [cite: 20]
    statut event_status DEFAULT 'pending' NOT NULL,
    created_by INT REFERENCES users(id) ON DELETE SET NULL,

    -- Récurrence (F33) [cite: 20]
    recurrence_id INT REFERENCES recurrence_rules(id) ON DELETE SET NULL,

    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_dates CHECK (end_date > start_date)
);

-- 4. Table de liaison flexible (Utilisateur OU Groupe au choix)
CREATE TABLE event_members (
    id SERIAL PRIMARY KEY, -- Une clé primaire simple pour autoriser les NULL plus bas
    event_id INT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,   -- Peut être NULL si c'est un groupe
    group_id INT REFERENCES groups(id) ON DELETE CASCADE, -- Peut être NULL si c'est un user solo

    -- Sécurité : Interdit d'avoir les deux à NULL en même temps
    CONSTRAINT chk_member_presence CHECK (user_id IS NOT NULL OR group_id IS NOT NULL)
);

-- 5. Index de performance (Critère p.6 : moins de 3 actions pour trouver) [cite: 38]
CREATE INDEX idx_events_dates ON events(start_date, end_date);
CREATE INDEX idx_events_statut ON events(statut);
CREATE INDEX idx_members_user ON event_members(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_members_group ON event_members(group_id) WHERE group_id IS NOT NULL;
