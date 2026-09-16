-- Reprise des métadonnées calendrier écrites par BFF Calendar dans la table auxiliaire
-- `calendar_event_metadata` (créée hors Liquibase) vers les colonnes de `events` et la table
-- `recurrence_rules` ajoutées en 04. Sans cette table, le changeset ne fait rien : les bases
-- neuves et celles qui n'ont jamais eu le BFF ne sont pas concernées.
--
-- Les données déjà présentes dans `events` ne sont pas écrasées, et `calendar_event_metadata`
-- n'est pas supprimée : son retrait interviendra dans une release ultérieure, une fois tous les
-- consommateurs migrés.

DO $$
DECLARE
    recurring RECORD;
    rule_id INTEGER;
    days SMALLINT[];
    rule_end TIMESTAMPTZ;
BEGIN
    IF to_regclass('public.calendar_event_metadata') IS NULL THEN
        RETURN;
    END IF;

    -- Catégorie, service et lieu : la valeur déjà saisie dans `events` gagne.
    UPDATE events e
    SET category = COALESCE(NULLIF(m.category, ''), e.category),
        service_label = COALESCE(e.service_label, NULLIF(m.service, '')),
        location = COALESCE(e.location, NULLIF(m.location, ''))
    FROM calendar_event_metadata m
    WHERE m.event_id = e.id
      AND e.service_group_id IS NULL;

    -- Récurrences : une règle par événement encore sans règle.
    FOR recurring IN
        SELECT e.id,
               e.start_date,
               e.end_date,
               e.visibility,
               e.owner_id,
               e.owner_group_id,
               e.created_by,
               m.recurrence
        FROM events e
        JOIN calendar_event_metadata m ON m.event_id = e.id
        WHERE e.recurrence_id IS NULL
          AND m.recurrence->>'frequency' IN ('daily', 'weekly', 'monthly')
        ORDER BY e.id
    LOOP
        days := NULLIF(
            ARRAY(
                SELECT day::SMALLINT
                FROM jsonb_array_elements_text(
                    CASE WHEN jsonb_typeof(recurring.recurrence->'daysOfWeek') = 'array'
                         THEN recurring.recurrence->'daysOfWeek'
                         ELSE '[]'::jsonb END
                ) AS day
                WHERE day ~ '^[0-6]$'
            ),
            ARRAY[]::SMALLINT[]
        );

        -- `endsOn` est le dernier jour inclus ; la règle se termine le lendemain à minuit UTC.
        rule_end := CASE
            WHEN NULLIF(recurring.recurrence->>'endsOn', '') ~ '^\d{4}-\d{2}-\d{2}$'
                THEN (((recurring.recurrence->>'endsOn')::DATE + 1)::TIMESTAMP AT TIME ZONE 'UTC')
        END;
        IF rule_end IS NOT NULL AND rule_end <= recurring.start_date THEN
            rule_end := NULL;
        END IF;

        INSERT INTO recurrence_rules (
            type_recurrence, intervalle, days_of_week, start_date, end_date,
            start_time, duration, visibility, owner_id, owner_group_id
        ) VALUES (
            (recurring.recurrence->>'frequency')::recurrence_type,
            GREATEST(COALESCE((recurring.recurrence->>'interval')::INTEGER, 1), 1),
            days,
            recurring.start_date,
            rule_end,
            (recurring.start_date AT TIME ZONE 'UTC')::TIME,
            recurring.end_date - recurring.start_date,
            recurring.visibility,
            CASE WHEN recurring.owner_group_id IS NULL
                 THEN COALESCE(recurring.owner_id, recurring.created_by) END,
            recurring.owner_group_id
        ) RETURNING id INTO rule_id;

        UPDATE events SET recurrence_id = rule_id, is_exception = false WHERE id = recurring.id;
    END LOOP;
END $$;
