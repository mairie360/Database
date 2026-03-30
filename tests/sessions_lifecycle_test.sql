BEGIN;
SELECT plan(6); -- On se concentre sur le flux logique

-- 1. Création d'un utilisateur actif
INSERT INTO users (id, first_name, last_name, email, password, status)
VALUES (100, 'Alice', 'Lifecycle', 'alice@test.com', 'pwd', 'active');

-- 2. Création d'une session pour Alice
INSERT INTO sessions (user_id, token_hash)
VALUES (100, 'alice_token');

SELECT ok(
    EXISTS (SELECT 1 FROM v_sessions WHERE user_id = 100),
    'Alice doit avoir une session active au départ'
);

-- 3. ARCHIVAGE de l'utilisateur
-- Selon tes triggers, l'update sur users va changer is_archived à TRUE
UPDATE users SET is_archived = TRUE, status = 'archived' WHERE id = 100;

-- 4. Vérification de l'intégrité (Le point crucial !)
-- Comme ta FK dans 'sessions' pointe sur (id, is_archived) 
-- ET que sessions.user_is_archived est bloqué à FALSE,
-- l'archivage du user DOIT avoir provoqué la suppression de la session (ON DELETE CASCADE)
-- ou le trigger doit avoir géré la rupture.

SELECT is_empty(
    $$ SELECT 1 FROM sessions WHERE user_id = 100 $$,
    'La session d''Alice doit être supprimée automatiquement (Cascade) quand Alice est archivée'
);

-- 5. Vérification du log de connexion final
SELECT ok(
    EXISTS (SELECT 1 FROM connection_logs WHERE user_id = 100 AND action_type = 'CLEANUP'),
    'Un log de type CLEANUP doit exister pour Alice suite à la suppression de sa session'
);

-- 6. Tentative de recréer une session pour un utilisateur archivé (Doit échouer)
-- Comme user_is_archived dans 'sessions' est restreint à FALSE par un CHECK,
-- et que le user id=100 a maintenant is_archived=TRUE dans la table 'users'.
SELECT throws_ok(
    $$ INSERT INTO sessions (user_id, user_is_archived, token_hash) VALUES (100, FALSE, 'new_token') $$,
    '23503', -- Violation de clé étrangère
    NULL,
    'Impossible de créer une session pour un utilisateur archivé (is_archived=TRUE en base != FALSE en session)'
);

-- 7. Test de restauration
SELECT lives_ok(
    $$ SELECT restore_user(100) $$,
    'La fonction restore_user doit fonctionner sans erreur'
);

SELECT is(
    (SELECT status FROM users WHERE id = 100),
    'offline',
    'Après restauration, le status doit être "offline"'
);

SELECT * FROM finish();
ROLLBACK;