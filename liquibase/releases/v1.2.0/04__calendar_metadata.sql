-- Métadonnées calendrier : on rapatrie dans `events` et `recurrence_rules` les
-- informations métier qui vivaient dans la table auxiliaire
-- `calendar_event_metadata` (créée hors Liquibase par le BFF). Cette table
-- auxiliaire n'est PAS supprimée ici : le retrait interviendra dans une release
-- ultérieure, une fois tous les consommateurs migrés.
--
-- Sécurité prod : les contraintes ajoutées sur des tables préexistantes sont
-- posées en NOT VALID. Elles s'appliquent immédiatement aux écritures futures
-- mais ne rescannent pas l'existant : la migration ne peut pas échouer sur des
-- données historiques non conformes, et le verrou ACCESS EXCLUSIVE reste bref.
-- Le VALIDATE CONSTRAINT est une étape d'exploitation ultérieure (après audit).

---
-- events
---
ALTER TABLE events ADD COLUMN IF NOT EXISTS category         VARCHAR(32) NOT NULL DEFAULT 'other';
ALTER TABLE events ADD COLUMN IF NOT EXISTS service_group_id INTEGER;
ALTER TABLE events ADD COLUMN IF NOT EXISTS service_label    VARCHAR(128);
ALTER TABLE events ADD COLUMN IF NOT EXISTS location         TEXT;

ALTER TABLE events DROP CONSTRAINT IF EXISTS fk_events_service_group;
ALTER TABLE events ADD CONSTRAINT fk_events_service_group
    FOREIGN KEY (service_group_id) REFERENCES groups(id) ON DELETE RESTRICT NOT VALID;

ALTER TABLE events DROP CONSTRAINT IF EXISTS chk_events_category;
ALTER TABLE events ADD CONSTRAINT chk_events_category
    CHECK (category IN ('meeting', 'activity', 'ceremony', 'other')) NOT VALID;

-- Le service est facultatif : soit un groupe identifié, soit un libellé libre,
-- jamais les deux.
ALTER TABLE events DROP CONSTRAINT IF EXISTS chk_events_service_exclusive;
ALTER TABLE events ADD CONSTRAINT chk_events_service_exclusive
    CHECK (num_nonnulls(service_group_id, service_label) <= 1) NOT VALID;

CREATE INDEX IF NOT EXISTS idx_events_service_group_id ON events (service_group_id);

---
-- recurrence_rules
---
-- Jours d'une récurrence hebdomadaire : 0 = dimanche ... 6 = samedi.
ALTER TABLE recurrence_rules ADD COLUMN IF NOT EXISTS days_of_week SMALLINT[];

ALTER TABLE recurrence_rules DROP CONSTRAINT IF EXISTS chk_recurrence_days_of_week;
ALTER TABLE recurrence_rules ADD CONSTRAINT chk_recurrence_days_of_week
    CHECK (
        days_of_week IS NULL
        OR (
            array_ndims(days_of_week) = 1
            AND cardinality(days_of_week) BETWEEN 1 AND 7
            AND array_position(days_of_week, NULL) IS NULL
            AND days_of_week <@ ARRAY[0, 1, 2, 3, 4, 5, 6]::smallint[]
        )
    ) NOT VALID;

-- Renforcement de `intervalle` : au moins 1, jamais NULL.
UPDATE recurrence_rules SET intervalle = 1 WHERE intervalle IS NULL OR intervalle < 1;
ALTER TABLE recurrence_rules ALTER COLUMN intervalle SET DEFAULT 1;
ALTER TABLE recurrence_rules ALTER COLUMN intervalle SET NOT NULL;

ALTER TABLE recurrence_rules DROP CONSTRAINT IF EXISTS chk_recurrence_intervalle;
ALTER TABLE recurrence_rules ADD CONSTRAINT chk_recurrence_intervalle
    CHECK (intervalle >= 1) NOT VALID;
