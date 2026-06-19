BEGIN;
SELECT plan(10);

---
--- 1. STRUCTURE & CONTRAINTES
---
SELECT has_table('rights');
SELECT col_is_pk('rights', ARRAY['role_id', 'permission_id']);
SELECT has_index('rights', 'idx_rights_permission_id');

---
--- 2. VÉRIFICATION DES DROITS ADMIN
---
-- On vérifie que l'Admin a bien ses droits (on utilise IN pour gérer le singulier/pluriel des ressources)
SELECT ok(
    EXISTS (
        SELECT 1 FROM rights ri
        JOIN roles ro ON ri.role_id = ro.id
        JOIN permissions p ON ri.permission_id = p.id
        JOIN resources res ON p.resource_id = res.id
        WHERE ro.name = 'Admin' AND res.name IN ('user', 'users') AND p.action = 'read_all'
    ),
    'L''Admin doit avoir la permission read_all sur les utilisateurs'
);

SELECT cmp_ok(
    (SELECT count(*)::INT FROM rights ri JOIN roles ro ON ri.role_id = ro.id WHERE ro.name = 'Admin'),
    '>', 0,
    'La table rights ne doit pas être vide pour l''Admin'
);

---
--- 3. VÉRIFICATION DES DROITS USER (MOINS DE PRIVILÈGES)
---
SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM rights ri
        JOIN roles ro ON ri.role_id = ro.id
        JOIN permissions p ON ri.permission_id = p.id
        JOIN resources res ON p.resource_id = res.id
        WHERE ro.name = 'User' AND p.action = 'read_all'
    ),
    'Un User standard ne doit PAS avoir le droit read_all (Principe du moindre privilège)'
);

---
--- 4. INTÉGRITÉ RÉFÉRENTIELLE (CASCADE)
---
-- Test : Si on supprime un rôle, ses droits disparaissent
INSERT INTO roles (name, description) VALUES ('TempRole', 'A supprimer');
INSERT INTO rights (role_id, permission_id) 
VALUES ((SELECT id FROM roles WHERE name = 'TempRole'), (SELECT min(id) FROM permissions));

DELETE FROM roles WHERE name = 'TempRole';
SELECT is_empty(
    $$ SELECT 1 FROM rights WHERE role_id NOT IN (SELECT id FROM roles) $$,
    'Les droits associés à un rôle supprimé doivent disparaître (CASCADE)'
);

-- Test : Si on supprime une permission, les droits associés disparaissent
SELECT lives_ok(
    $$ DELETE FROM permissions WHERE id = (SELECT max(id) FROM permissions) $$,
    'La suppression d''une permission doit nettoyer la table rights sans erreur'
);

---
--- 5. SÉCURITÉ (DOUBLONS)
---
SELECT throws_ok(
    format('INSERT INTO rights (role_id, permission_id) VALUES (%L, %L)', 
        (SELECT role_id FROM rights LIMIT 1), 
        (SELECT permission_id FROM rights LIMIT 1)
    ),
    '23505',
    NULL,
    'La clé primaire composite doit empêcher d''attribuer deux fois le même droit au même rôle'
);

---
--- 6. REQUÊTE DE PERFORMANCE (Ce que ton Rust fera)
---
SELECT lives_ok(
    $$ 
    SELECT res.name, p.action 
    FROM rights ri
    JOIN permissions p ON ri.permission_id = p.id
    JOIN resources res ON p.resource_id = res.id
    WHERE ri.role_id = (SELECT id FROM roles WHERE name = 'Admin')
    $$,
    'La jointure de récupération des droits doit être valide et performante'
);

SELECT * FROM finish();
ROLLBACK;