BEGIN;
SELECT plan(10); -- Nous programmons 10 tests unitaires

---
--- 1. PRÉPARATION DES DONNÉES (SEED)
---

-- Création des utilisateurs requis par le plan de test (F11, F30)
-- Utilisation d'IDs élevés (400+) pour ne jamais entrer en conflit avec ton utilisateur ID 1
INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (400, 'Jean', 'Responsable', 'jean.responsable@mairie.fr', 'password'),
    (401, 'Alice', 'Employé', 'alice.employe@mairie.fr', 'password'),
    (402, 'Robert', 'Maire', 'robert.maire@mairie.fr', 'password')
ON CONFLICT (id) DO NOTHING;

-- Création d'un groupe pour le test de liaison (F32)
INSERT INTO groups (id, name, owner_id)
VALUES (10, 'Service Urbanisme', 400)
ON CONFLICT (id) DO NOTHING;

-- Création d'une règle de récurrence (F33)
INSERT INTO recurrence_rules (id, type_recurrence, intervalle, date_fin)
VALUES (1, 'weekly', 1, '2026-12-31 00:00:00')
ON CONFLICT (id) DO NOTHING;

---
--- 2. VÉRIFICATION DE LA STRUCTURE
---
SELECT has_table('events');
SELECT has_table('event_members');
SELECT has_table('recurrence_rules');

---
--- 3. SÉCURITÉ : CONTRAINTES DE VALIDATION (CHECK CONSTRAINTS)
---

-- Test 1 : Empêcher la création si la date de fin est antérieure à la date de début
SELECT throws_ok(
    $$ INSERT INTO events (name, start_date, end_date, created_by)
       VALUES ('Événement Invalide', '2026-06-01 14:00:00', '2026-06-01 12:00:00', 401) $$,
    '23514', -- Code d'erreur standard Postgres pour Check Violation
    NULL,
    'La contrainte chk_dates doit bloquer une date_fin antérieure à start_date'
);

-- Test 2 : Empêcher un membre de liaison d'être totalement vide (Ni User, Ni Groupe)
-- Utilisation de l'ID 901 pour l'événement pour éviter tout conflit avec un potentiel ID 1 existant
INSERT INTO events (id, name, start_date, end_date, statut, created_by)
VALUES (901, 'Réunion Test', '2026-06-01 10:00:00', '2026-06-01 11:00:00', 'pending', 401);

SELECT throws_ok(
    $$ INSERT INTO event_members (event_id, user_id, group_id) VALUES (901, NULL, NULL) $$,
    '23514', -- Check Violation
    NULL,
    'La contrainte chk_member_presence doit interdire d''avoir user_id ET group_id à NULL'
);

---
--- 4. SCÉNARIOS FONCTIONNELS (LIAISONS FLEXIBLES)
---

-- Test 3 : Liaison valide à un GROUPE uniquement (F32)
SELECT lives_ok(
    $$ INSERT INTO event_members (event_id, group_id) VALUES (901, 10) $$,
    'L''événement doit pouvoir être lié à un groupe sans spécifier d''utilisateur'
);

-- Test 4 : Liaison valide à un UTILISATEUR unique
-- Utilisation de l'ID 902 pour l'événement
INSERT INTO events (id, name, start_date, end_date, statut, created_by)
VALUES (902, 'Point RH Solo', '2026-06-02 14:00:00', '2026-06-02 15:00:00', 'pending', 400);

SELECT lives_ok(
    $$ INSERT INTO event_members (event_id, user_id) VALUES (902, 401) $$,
    'L''événement doit pouvoir être lié à un utilisateur unique sans spécifier de groupe'
);

---
--- 5. CYCLE DE VIE & SUPPRESSION (ON DELETE CASCADE)
---

-- Test 5 : Vérification du statut de validation initial à 'pending' par défaut (F27)
SELECT is(
    (SELECT statut FROM events WHERE id = 901),
    'pending'::event_status,
    'Un nouvel événement créé doit être au statut ''pending'' par défaut'
);

-- Test 6 : Validation de l'événement par un décideur (F30)
UPDATE events SET statut = 'validated' WHERE id = 901;
SELECT is(
    (SELECT statut FROM events WHERE id = 901),
    'validated'::event_status,
    'Le statut doit passer à ''validated'' après action du Responsable ou du Maire'
);

-- Test 7 : Nettoyage en cascade automatique lors de la suppression d'un événement (F29)
-- Si on supprime l'événement 901, sa liaison dans event_members doit disparaître d'elle-même.
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
