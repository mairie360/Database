BEGIN;
SELECT plan(7); -- On annonce 7 tests

-- Test 1: Vérification de l'existence de la table
SELECT has_table('users', 'La table users doit exister');

-- Test 2: Vérification du statut par défaut
INSERT INTO users (first_name, last_name, email, password) 
VALUES ('Unit', 'Test', 'unit@test.com', 'hash');

SELECT results_eq(
    'SELECT status FROM users WHERE email = ''unit@test.com''',
    $$VALUES ('offline'::varchar)$$,
    'Le statut par défaut doit être offline'
);

-- Test 3: Vérification du trigger d''audit sur INSERT
SELECT is(
    (SELECT action_type FROM users_audit_log WHERE user_id = (SELECT id FROM users WHERE email = 'unit@test.com')),
    'CREATE'::user_audit_action,
    'L''audit doit enregistrer une action CREATE'
);

-- Test 4: Test du Soft Delete via la vue
DELETE FROM v_users_active WHERE email = 'unit@test.com';

SELECT results_eq(
    'SELECT is_archived, status FROM users WHERE email = ''unit@test.com''',
    $$VALUES (true, 'archived'::varchar)$$,
    'Le DELETE sur la vue doit archiver l''utilisateur sans supprimer la ligne'
);

-- Test 5: Vérification de l''audit sur l''archivage (Soft Delete)
SELECT is(
    (SELECT action_type FROM users_audit_log WHERE action_type = 'ARCHIVE' LIMIT 1),
    'ARCHIVE'::user_audit_action,
    'L''audit doit avoir capturé le changement vers ARCHIVE'
);

-- Test 6: Test de la fonction de restauration
SELECT lives_ok(
    format('SELECT restore_user(%L)', (SELECT id FROM users WHERE email = 'unit@test.com')),
    'La fonction restore_user ne doit pas renvoyer d''erreur'
);

-- Test 7: Sécurité - L''audit est-il vraiment protégé ?
SELECT throws_ok(
    'DELETE FROM users_audit_log',
    'P0001', -- Code erreur PostgreSQL pour RAISE EXCEPTION
    NULL,
    'Le trigger doit empêcher la suppression de l''audit'
);

SELECT * FROM finish();
ROLLBACK;