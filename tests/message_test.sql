BEGIN;
SELECT plan(15); -- Nous programmons désormais 15 tests unitaires

---
--- 1. PRÉPARATION DES DONNÉES (SEED)
---

-- Création des utilisateurs requis
INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (500, 'Jean', 'Responsable', 'jean.responsable@mairie.fr', 'password'),
    (501, 'Alice', 'Employé', 'alice.employe@mairie.fr', 'password'),
    (502, 'Robert', 'Maire', 'robert.maire@mairie.fr', 'password')
ON CONFLICT (id) DO NOTHING;

-- Création d'un groupe (Service Police Municipale)
INSERT INTO groups (id, name, owner_id)
VALUES (20, 'Police Municipale', 500)
ON CONFLICT (id) DO NOTHING;

-- Simulation de l'appartenance au groupe dans la table de liaison de ton système (ex: group_users)
INSERT INTO group_users (group_id, user_id)
VALUES (20, 500), (20, 501), (20, 502)
ON CONFLICT DO NOTHING;

---
--- 2. VÉRIFICATION DE LA STRUCTURE DES TABLES
---
SELECT has_table('conversations');
SELECT has_table('conversation_members');
SELECT has_table('messages');

---
--- 3. SCÉNARIOS FONCTIONNELS : CRÉATION ET ACCÈS (LIAISONS FLEXIBLES)
---

-- Test 1 : Création d'un chat lié à un GROUPE (ID conversation = 801)
INSERT INTO conversations (id, title, group_id)
VALUES (801, 'Chat Officiel - Police Municipale', 20);

SELECT is(
    (SELECT group_id FROM conversations WHERE id = 801),
    20,
    'La conversation de groupe doit être directement et dynamiquement liée au groupe_id'
);

-- Test 2 : Création d'un chat privé entre PLUSIEURS utilisateurs (ID conversation = 802)
INSERT INTO conversations (id, title, group_id)
VALUES (802, 'Organisation Pot de Départ', NULL);

SELECT lives_ok(
    $$
    INSERT INTO conversation_members (conversation_id, user_id) VALUES (802, 500);
    INSERT INTO conversation_members (conversation_id, user_id) VALUES (802, 501);
    $$,
    'Un chat privé multi-utilisateurs doit pouvoir accueillir des membres individuellement'
);

-- Test 3 : Vérification du nombre initial de membres dans le chat privé
SELECT is(
    (SELECT count(*)::INT FROM conversation_members WHERE conversation_id = 802),
    2,
    'Le chat privé initialisé doit contenir exactement 2 membres'
);

---
--- 4. RETIRER / EXCLURE UN UTILISATEUR
---

-- Test 4 : RETRAIT D''UN UTILISATEUR D''UN CHAT PRIVÉ (Correction des $$$ ici)
SELECT lives_ok(
    $$ DELETE FROM conversation_members WHERE conversation_id = 802 AND user_id = 501 $$,
    'Le retrait d''un membre d''un chat privé se fait par la suppression de sa ligne dans conversation_members'
);

SELECT is(
    (SELECT count(*)::INT FROM conversation_members WHERE conversation_id = 802 AND user_id = 501),
    0,
    'L''agent Alice ne doit plus figurer parmi les membres actifs du chat privé'
);

-- Test 5 : RETRAIT D''UN UTILISATEUR D''UN CHAT DE GROUPE (EXCLUSION)
INSERT INTO conversation_members (conversation_id, user_id, is_excluded)
VALUES (801, 502, TRUE);

SELECT ok(
    EXISTS (SELECT 1 FROM conversation_members WHERE conversation_id = 801 AND user_id = 502 AND is_excluded = TRUE),
    'Pour retirer un membre d''un chat lié à un groupe, on doit pouvoir le marquer comme exclu (is_excluded = TRUE)'
);

---
--- 5. SÉCURITÉ & HISTORIQUE (CONTRAINTES & CASCADE)
---

-- Test 6 : Un utilisateur non exclu doit pouvoir envoyer un message
SELECT lives_ok(
    $$ INSERT INTO messages (conversation_id, sender_id, content) VALUES (801, 500, 'Bonjour l''équipe !') $$,
    'Un membre légitime doit pouvoir enregistrer un message dans l''historique'
);

-- Test 7 : Nettoyage en cascade (ON DELETE CASCADE)
INSERT INTO conversations (id, title, group_id) VALUES (899, 'Temp Chat', NULL);
INSERT INTO conversation_members (conversation_id, user_id) VALUES (899, 500);
DELETE FROM conversations WHERE id = 899;

SELECT is(
    (SELECT count(*)::INT FROM conversation_members WHERE conversation_id = 899),
    0,
    'La suppression d''un salon de chat doit nettoyer automatiquement les lignes de liaison associées'
);

---
--- 6. VALIDATION DES COMPTEURS DE MESSAGES NON LUS (TRIGGERS)
---

-- CAS 1 : Chat Privé (On réintègre Alice pour le test)
INSERT INTO conversation_members (conversation_id, user_id) VALUES (802, 501);

INSERT INTO messages (conversation_id, sender_id, content)
VALUES (802, 500, 'Est-ce que le trigger fonctionne ?');

-- Test 8 : Vérification de l'incrémentation automatique (Chat Privé)
SELECT is(
    (SELECT unread_count FROM unread_counters WHERE conversation_id = 802 AND user_id = 501),
    1,
    'Le compteur de l''agent 501 doit s''être incrémenté automatiquement à 1 suite au message'
);

-- Test 9 : Test du nettoyage automatique à 0
UPDATE unread_counters SET unread_count = 0 WHERE conversation_id = 802 AND user_id = 501;

SELECT ok(
    NOT EXISTS (SELECT 1 FROM unread_counters WHERE conversation_id = 802 AND user_id = 501),
    'La ligne dans unread_counters doit avoir été supprimée automatiquement car le compteur est tombé à 0'
);

-- CAS 2 : Chat de Groupe avec Utilisateur Exclu
-- Rappel : Robert (502) est exclu de la conversation de groupe 801 via conversation_members
-- On s'assure qu'un message à l'intérieur du groupe 801 déclenche les règles pour les autres
INSERT INTO conversations (id, title, group_id) VALUES (803, 'Salon Service Police', 20);
INSERT INTO conversation_members (conversation_id, user_id, is_excluded) VALUES (803, 502, TRUE);

INSERT INTO messages (conversation_id, sender_id, content)
VALUES (803, 500, 'Message important pour le service.');

-- Test 10 : L'utilisateur banni/exclu ne doit pas recevoir la notification
SELECT ok(
    NOT EXISTS (SELECT 1 FROM unread_counters WHERE conversation_id = 803 AND user_id = 502),
    'L''utilisateur banni du groupe (502) ne doit pas avoir de ligne de notification créée dans unread_counters'
);

-- Test 11 : Mais les autres membres non exclus du groupe doivent quand même la recevoir
SELECT is(
    (SELECT unread_count FROM unread_counters WHERE conversation_id = 803 AND user_id = 501),
    1,
    'L''agent Alice (501), membre normal du groupe, doit correctement recevoir son compteur à 1'
);

---
--- FIN DES TESTS
---
SELECT * FROM finish();
ROLLBACK;
