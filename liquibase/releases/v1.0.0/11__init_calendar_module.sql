-- 1. Enums alignés (Sécurisés pour la réexécution)
DO $$ BEGIN
    CREATE TYPE event_validation_status AS ENUM ('pending', 'validated', 'refused');
    CREATE TYPE recurrence_type AS ENUM ('daily', 'weekly', 'monthly');
    CREATE TYPE event_visibility AS ENUM ('private', 'public');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- 2. Table Récurrence
CREATE TABLE recurrence_rules (
    id SERIAL PRIMARY KEY,
    type_recurrence recurrence_type NOT NULL,
    intervalle INT DEFAULT 1,

    -- On garde le début de série pour savoir QUAND ça commence
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ DEFAULT (now() + interval '5 years'),

    -- On stocke l'heure locale et la durée (indépendante de la date)
    start_time TIME NOT NULL,
    duration INTERVAL NOT NULL,

    owner_id INT REFERENCES users(id) ON DELETE SET NULL,
    owner_group_id INT REFERENCES groups(id) ON DELETE SET NULL,

    visibility event_visibility DEFAULT 'private' NOT NULL,

    -- Garantit que les dates de fin sont après les dates de début
    CONSTRAINT chk_dates CHECK (end_date > start_date),

    -- Garantit que l'événement a un propriétaire (soit un user, soit un groupe)
    CONSTRAINT chk_member_presence CHECK (owner_id IS NOT NULL OR owner_group_id IS NOT NULL),

    -- Empêche le doublon (soit l'un, soit l'autre, jamais les deux sur la même ligne)
    CONSTRAINT chk_exclusive_member CHECK (
        (owner_id IS NOT NULL AND owner_group_id IS NULL)
        OR
        (owner_id IS NULL AND owner_group_id IS NOT NULL)
    )
);

-- 3. Table Événements
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ NOT NULL,

    created_by INT REFERENCES users(id) ON DELETE SET NULL,
    recurrence_id INT REFERENCES recurrence_rules(id) ON DELETE SET NULL,
    is_exception BOOLEAN DEFAULT FALSE,
    visibility event_visibility DEFAULT 'private' NOT NULL,

    -- Remplacement du polymorphisme par des clés étrangères natives
    owner_id INT REFERENCES users(id) ON DELETE SET NULL,
    owner_group_id INT REFERENCES groups(id) ON DELETE SET NULL,

    -- Garantit que les dates de fin sont après les dates de début
    CONSTRAINT chk_dates CHECK (end_date > start_date),

    CONSTRAINT chk_recurrence CHECK (
        (recurrence_id IS NOT NULL AND is_exception IS NOT NULL)
        OR
        (recurrence_id IS NULL AND is_exception IS NULL)
    ),

    -- Garantit que l'événement a un propriétaire (soit un user, soit un groupe)
    CONSTRAINT chk_member_presence CHECK (owner_id IS NOT NULL OR owner_group_id IS NOT NULL),

    -- Empêche le doublon (soit l'un, soit l'autre, jamais les deux sur la même ligne)
    CONSTRAINT chk_exclusive_member CHECK (
        (owner_id IS NOT NULL AND owner_group_id IS NULL)
        OR
        (owner_id IS NULL AND owner_group_id IS NOT NULL)
    )
);

-- 4. Table de liaison des membres (Inscriptions)
CREATE TABLE event_members (
    event_id INT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    validation_status event_validation_status DEFAULT 'pending' NOT NULL
);

-- 5. Table de liaison des membres (Sauvegarde)
CREATE TABLE recurrence_members (
    recurrence_id INT NOT NULL REFERENCES recurrence_rules(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    group_id INT REFERENCES groups(id) ON DELETE CASCADE,

    CONSTRAINT chk_member_presence CHECK (user_id IS NOT NULL OR group_id IS NOT NULL),

    -- Empêche le doublon (soit l'un, soit l'autre, jamais les deux sur la même ligne)
    CONSTRAINT chk_exclusive_member CHECK (
        (user_id IS NOT NULL AND group_id IS NULL)
        OR
        (user_id IS NULL AND group_id IS NOT NULL)
    )
); -- Correction : Ajout de la parenthèse fermante manquante

-- 5. Table des paramètres de calendrier
CREATE TABLE user_calendar_params (
    default_event_visibility event_visibility DEFAULT 'private' NOT NULL,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE
); -- Correction : Retrait de la virgule en trop avant la parenthèse

-- 6. Index de performance
CREATE INDEX idx_events_dates ON events(start_date, end_date);
CREATE INDEX idx_members_user ON event_members(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_members_event_status ON event_members(event_id, validation_status);
CREATE INDEX idx_user_calendar_params ON user_calendar_params(user_id);

-- Anti-doublons d'inscription
CREATE UNIQUE INDEX idx_unique_user_event ON event_members(event_id, user_id) WHERE user_id IS NOT NULL;

---
-- 7. INSERTION DES DONNÉES DE SÉCURITÉ
---

-- Ressources
INSERT INTO resources (name, description) VALUES
    ('events', 'Gestion des événements')
ON CONFLICT (name) DO NOTHING;

-- Permissions (Correction : Syntaxe VALUES multiple pour insérer plusieurs lignes)
INSERT INTO permissions (resource_id, action)
SELECT id, action FROM resources,
(VALUES ('create'), ('read'), ('update'), ('delete'), ('read_all'), ('update_all'), ('delete_all')) AS t(action)
WHERE name = 'events'
ON CONFLICT (resource_id, action) DO NOTHING;

-- Droits Admin
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Admin' AND res.name = 'events'
AND p.action IN ('read_all', 'create', 'update_all', 'delete_all')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Maire
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Maire' AND res.name = 'events'
AND p.action IN ('read', 'create', 'update', 'delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Responsable
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Responsable' AND res.name = 'events'
AND p.action IN ('read', 'create', 'update', 'delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits User
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'User' AND res.name = 'events'
AND p.action IN ('read', 'update', 'delete', 'create')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Guest
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Guest' AND res.name = 'events'
AND p.action IN ('read')
ON CONFLICT (role_id, permission_id) DO NOTHING;
