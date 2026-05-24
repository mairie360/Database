BEGIN;
SELECT plan(11); -- Nous programmons 11 tests unitaires

---
--- 1. PRÉPARATION DES DONNÉES (SEED)
---

-- Création des utilisateurs requis (IDs 500+ pour éviter les conflits avec l'ID 1)
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
-- On lie directement le groupe_id sans dupliquer les utilisateurs
INSERT INTO conversations (id, title, group_id)
VALUES (801, 'Chat Officiel - Police Municipale', 20);

SELECT is(
    (SELECT group_id FROM conversations WHERE id = 801),
    20,
    'La conversation de groupe doit être directement et dynamiquement liée au groupe_id'
);

-- Test 2 : Création d'un chat privé entre PLUSIEURS utilisateurs (ID conversation = 802)
-- Le group_id reste NULL, on alimente manuellement la table de liaison
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

-- Test 4 : RETRAIT D''UN UTILISATEUR D''UN CHAT PRIVÉ
-- Dans un chat privé, retirer quelqu'un équivaut à supprimer sa ligne de liaison
SELECT lives_ok(
    $$ DELETE FROM conversation_members WHERE conversation_id = 802 AND user_id = 501 $$,
    'Le retrait d''un membre d''un chat privé se fait par la suppression de sa ligne dans conversation_members'
);

SELECT is(
    (SELECT count(*)::INT FROM conversation_members WHERE conversation_id = 802 AND user_id = 501),
    0,
    'L''agent Dupond ne doit plus figurer parmi les membres actifs du chat privé'
);

-- Test 5 : RETRAIT D''UN UTILISATEUR D''UN CHAT DE GROUPE (EXCLUSION)
-- L'agent Durand fait partie du groupe Police (ID 20). Pour lui couper l'accès au chat
-- sans le supprimer du groupe de travail global, on insère son ID avec le flag `is_excluded = TRUE`
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
-- Si un salon/chat est supprimé, toutes ses dépendances (membres, messages) doivent sauter
DELETE FROM conversations WHERE id = 801;

SELECT is(
    (SELECT count(*)::INT FROM conversation_members WHERE conversation_id = 801),
    0,
    'La suppression d''un salon de chat doit nettoyer automatiquement les lignes de liaison associées'
);

---
--- FIN DES TESTS
---
SELECT * FROM finish();
ROLLBACK;
