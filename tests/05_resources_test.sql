BEGIN;
SELECT plan(12); -- On prévoit 12 tests

---
--- 1. STRUCTURE & DONNÉES DE RÉFÉRENCE
---

SELECT has_table('resources');

SELECT is(
    (SELECT count(*)::INT FROM resources WHERE name IN ('users', 'roles', 'sessions', 'session_setting')),
    4,
    'Les 4 ressources de base doivent être présentes dans la table resources'
);

---
--- 2. VÉRIFICATION DES VUES SÉCURISÉES (SECURABLES)
---

-- Test Vue Users
SELECT has_view('v_securable_users');
SELECT is(
    (SELECT resource_id FROM v_securable_users LIMIT 1),
    (SELECT id FROM resources WHERE name = 'users'),
    'La vue v_securable_users doit injecter le bon resource_id'
);

-- Test Vue Roles
SELECT has_view('v_securable_roles');
SELECT is(
    (SELECT resource_id FROM v_securable_roles WHERE name = 'Admin'),
    (SELECT id FROM resources WHERE name = 'roles'),
    'La vue v_securable_roles doit injecter le bon resource_id pour le rôle Admin'
);

-- Test Vue Session Settings (Cas table ligne unique)
SELECT has_view('v_securable_session_settings');
SELECT is(
    (SELECT resource_id FROM v_securable_session_settings LIMIT 1),
    (SELECT id FROM resources WHERE name = 'session_setting' LIMIT 1),
    'La vue v_securable_session_settings doit fonctionner même pour une table à ligne unique'
);

---
--- 3. INTÉGRITÉ & TRIGGERS
---

-- Test du trigger updated_at sur resources
SELECT ok(
    (SELECT updated_at FROM resources WHERE name = 'users') <= now(),
    'Le timestamp initial doit être correct'
);

-- On simule une modification
UPDATE resources SET description = 'Nouveau texte' WHERE name = 'users';

SELECT ok(
    updated_at >= now() - interval '1 second',
    'Le trigger trg_resources_updated_at doit mettre à jour updated_at lors d''un UPDATE'
) FROM resources WHERE name = 'users';

---
--- 4. TESTS DE LIAISON DYNAMIQUE
---

-- Vérifier que si on crée un utilisateur, il apparaît dans la vue avec son resource_id
INSERT INTO users (first_name, last_name, email, password)
VALUES ('Jean', 'Ressource', 'test.res@mairie.fr', 'pwd');

SELECT ok(
    EXISTS (SELECT 1 FROM v_securable_users WHERE email = 'test.res@mairie.fr' AND resource_id IS NOT NULL),
    'Un nouvel utilisateur doit être automatiquement visible dans la vue sécurisée avec son ID de ressource'
);

-- Test de robustesse : Si on change le nom de la ressource (pas recommandé mais testons la cohérence)
UPDATE resources SET name = 'user_account' WHERE name = 'users';

-- La vue devrait maintenant retourner NULL ou échouer si le nom est hardcodé sans jointure robuste
-- Dans ton SQL, tu fais (SELECT id FROM resources WHERE name = 'users')
-- Ce test va échouer si tu ne mets pas à jour le nom, ce qui prouve que ton système est sensible aux noms.
SELECT is(
    (SELECT resource_id FROM v_securable_users LIMIT 1),
    NULL,
    'La ressource_id doit devenir NULL si le nom dans la table resources ne correspond plus (Comportement attendu du sous-select)'
);

SELECT * FROM finish();
ROLLBACK;