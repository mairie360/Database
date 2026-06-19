BEGIN;
SELECT plan(11); -- Nous programmons 14 tests unitaires

---
--- 1. PRÉPARATION DES DONNÉES (SEED)
---

-- Création des utilisateurs requis par le plan de test
INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (400, 'Jean', 'Responsable', 'jean.responsable@mairie.fr', 'password'),
    (401, 'Alice', 'Employé', 'alice.employe@mairie.fr', 'password'),
    (402, 'Robert', 'Maire', 'robert.maire@mairie.fr', 'password')
ON CONFLICT (id) DO NOTHING;

-- Création d'un groupe pour les tests
INSERT INTO groups (id, name, owner_id)
VALUES (10, 'Service Urbanisme', 400)
ON CONFLICT (id) DO NOTHING;

-- Création d'une règle de récurrence
INSERT INTO recurrence_rules (
    id, type_recurrence, intervalle,
    start_date, start_time, duration,
    owner_id, visibility
) VALUES (
    1, 'weekly', 1,
    '2026-12-31 00:00:00+00', '09:00:00', '01:00:00',
    400, 'private'
)
ON CONFLICT (id) DO NOTHING;

---
--- 2. VÉRIFICATION DE LA STRUCTURE
---
SELECT has_table('events');
SELECT has_table('event_members');
SELECT has_table('recurrence_rules');
SELECT has_table('user_calendar_params');

---
--- 3. SÉCURITÉ : CONTRAINTES DE VALIDATION (CHECK CONSTRAINTS)
---

-- Test 5 : Empêcher la création si la date de fin est antérieure
SELECT throws_ok(
    $$ INSERT INTO events (name, start_date, end_date, created_by, owner_id)
       VALUES ('Événement Invalide', '2026-06-01 14:00:00', '2026-06-01 12:00:00', 401, 401) $$,
    '23514',
    NULL,
    'La contrainte chk_dates doit bloquer une end_date antérieure à start_date'
);

-- Test 6 : (Sur events) Un événement DOIT avoir un propriétaire (User ou Groupe)
SELECT throws_ok(
    $$ INSERT INTO events (name, start_date, end_date, created_by, owner_id, owner_group_id)
       VALUES ('Événement Sans Propriétaire', '2026-06-01 10:00:00', '2026-06-01 11:00:00', 401, NULL, NULL) $$,
    '23514',
    NULL,
    'chk_member_presence (events) interdit de créer un événement sans owner_id ni owner_group_id'
);

-- Test 7 : (Sur events) Exclusivité du propriétaire (Pas les deux en même temps)
SELECT throws_ok(
    $$ INSERT INTO events (name, start_date, end_date, created_by, owner_id, owner_group_id)
       VALUES ('Événement Double Owner', '2026-06-01 10:00:00', '2026-06-01 11:00:00', 401, 401, 10) $$,
    '23514',
    NULL,
    'chk_exclusive_member (events) interdit d''avoir un owner_id ET un owner_group_id simultanément'
);

-- Création d'un événement valide pour tester les membres (ID = 901)
INSERT INTO events (id, name, start_date, end_date, created_by, owner_id)
VALUES (901, 'Réunion Test', '2026-06-01 10:00:00', '2026-06-01 11:00:00', 401, 401);

-- Test 11 : Liaison valide à un UTILISATEUR unique
SELECT lives_ok(
    $$ INSERT INTO event_members (event_id, user_id) VALUES (901, 402) $$,
    'L''inscription doit pouvoir être liée à un utilisateur unique sans spécifier de groupe'
);

---
--- 5. CYCLE DE VIE & SUPPRESSION (ON DELETE CASCADE)
---

-- Test 8 : Vérification du statut de validation initial (Il est maintenant dans event_members)
SELECT is(
    (SELECT validation_status FROM event_members WHERE event_id = 901 AND user_id = 402),
    'pending'::event_validation_status,
    'Une nouvelle invitation (event_members) doit être au statut ''pending'' par défaut'
);

-- Test 9 : Validation de l'événement par l'invité
UPDATE event_members SET validation_status = 'validated' WHERE event_id = 901 AND user_id = 402;
SELECT is(
    (SELECT validation_status FROM event_members WHERE event_id = 901 AND user_id = 402),
    'validated'::event_validation_status,
    'Le statut dans event_members doit pouvoir passer à ''validated'''
);

-- Test 10 : Nettoyage en cascade automatique
DELETE FROM events WHERE id = 901;

SELECT is(
    (SELECT count(*)::INT FROM event_members WHERE event_id = 901),
    0,
    'La suppression de l''événement doit nettoyer automatiquement event_members (CASCADE)'
);

---
--- FIN DES TESTS
---
SELECT * FROM finish();
ROLLBACK;
