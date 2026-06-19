BEGIN;
SELECT plan(10); 

-- 1. STRUCTURE (4 tests)
SELECT has_table('permissions');
SELECT col_is_pk('permissions', 'id');
SELECT has_index('permissions', 'idx_permissions_resource_id');
SELECT col_is_unique('permissions', ARRAY['resource_id', 'action'], 'Unicité ressource + action');

-- 2. VÉRIFICATION DES INSERTIONS (2 tests)
-- On vérifie le compte global pour éviter les soucis de noms singulier/pluriel
SELECT cmp_ok(
    (SELECT count(*)::INT FROM permissions), '>=', 15,
    'Il doit y avoir au moins 15 permissions générées (User, Roles, Sessions, Settings)'
);

-- On vérifie l'existence d'une permission critique par son action
SELECT ok(
    EXISTS (SELECT 1 FROM permissions WHERE action = 'read_all'),
    'La permission "read_all" doit être présente globalement'
);

-- 3. SÉCURITÉ (2 tests)
SELECT throws_ok(
    $$ INSERT INTO permissions (resource_id, action) VALUES ((SELECT min(id) FROM resources), 'hack') $$,
    '23514', 
    NULL,
    'Le CHECK constraint doit rejeter les actions invalides'
);

-- Test unique : on tente d'insérer un doublon sur la première ligne trouvée
SELECT throws_ok(
    format('INSERT INTO permissions (resource_id, action) VALUES (%L, %L)', 
        (SELECT resource_id FROM permissions LIMIT 1), 
        (SELECT action FROM permissions LIMIT 1)
    ),
    '23505',
    NULL,
    'L''unicité doit empêcher les doublons'
);

-- 4. INTÉGRITÉ CASCADE (1 test)
-- On crée une ressource de test et on la supprime
INSERT INTO resources (name) VALUES ('temp_cleanup_test');
INSERT INTO permissions (resource_id, action) VALUES ((SELECT id FROM resources WHERE name = 'temp_cleanup_test'), 'read');
DELETE FROM resources WHERE name = 'temp_cleanup_test';

SELECT is_empty(
    $$ SELECT 1 FROM permissions WHERE resource_id NOT IN (SELECT id FROM resources) $$,
    'Le ON DELETE CASCADE doit nettoyer les permissions orphelines'
);

-- 5. LOGIQUE MÉTIER (1 test)
SELECT lives_ok(
    $$ UPDATE permissions SET description = 'Test Update' WHERE id = (SELECT min(id) FROM permissions) $$,
    'La description doit être modifiable sans erreur'
);

SELECT * FROM finish();
ROLLBACK;