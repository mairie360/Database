BEGIN;
SELECT plan(10); -- On prévoit 10 tests

---
--- 1. TESTS DE STRUCTURE & DONNÉES INITIALES
---

SELECT has_table('roles');
SELECT has_table('user_roles');

SELECT is(
    (SELECT count(*)::INT FROM roles WHERE name IN ('Admin', 'User', 'Guest')),
    3,
    'Les 3 rôles par défaut doivent être présents'
);

---
--- 2. PROTECTION DES RÔLES SYSTÈMES
---

-- Test protection contre la suppression
SELECT throws_ok(
    $$ DELETE FROM roles WHERE name = 'Admin' $$,
    'Suppression impossible : le rôle "Admin" est critique pour le système.',
    'Le trigger doit empêcher la suppression du rôle Admin'
);

-- Test protection contre le renommage
SELECT throws_ok(
    $$ UPDATE roles SET name = 'SuperUser' WHERE name = 'Admin' $$,
    'Modification interdite : le nom du rôle "Admin" est réservé.',
    'Le trigger doit empêcher de renommer le rôle Admin'
);

---
--- 3. ATTRIBUTION ET CYCLE DE VIE USER/ROLE
---

-- Préparation : Un utilisateur de test
INSERT INTO users (id, first_name, last_name, email, password, status)
VALUES (200, 'Marc', 'RoleTest', 'marc@test.com', 'pwd', 'active');

-- Test attribution de rôle
INSERT INTO user_roles (user_id, role_id) 
VALUES (200, (SELECT id FROM roles WHERE name = 'User'));

SELECT ok(
    EXISTS (SELECT 1 FROM user_roles WHERE user_id = 200),
    'Marc doit avoir le rôle User'
);

---
--- 4. TEST DE SÉCURITÉ : ARCHIVAGE ET RÔLES
---

-- Scénario : On archive l'utilisateur. 
-- Comme pour les sessions, l'update sur users (is_archived = TRUE)
-- DOIT échouer si on n'a pas nettoyé user_roles, OU le trigger de nettoyage doit agir.

-- Note : Il te manque le trigger de nettoyage pour user_roles (similaire à celui des sessions)
-- Ajoutons-le dans le test pour valider qu'il est nécessaire.

CREATE OR REPLACE FUNCTION fn_cleanup_user_roles_on_archive()
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.is_archived = FALSE AND NEW.is_archived = TRUE) THEN
        DELETE FROM user_roles WHERE user_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_05_cleanup_roles_on_archive
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_cleanup_user_roles_on_archive();

-- Maintenant on test l'archivage
SELECT lives_ok(
    $$ UPDATE users SET is_archived = TRUE, status = 'archived' WHERE id = 200 $$,
    'L''archivage doit réussir car le nouveau trigger nettoie user_roles'
);

SELECT is_empty(
    $$ SELECT 1 FROM user_roles WHERE user_id = 200 $$,
    'Les rôles de Marc doivent être supprimés lors de son archivage'
);

-- Test : Impossible d'ajouter un rôle à un archivé
-- (Car user_is_archived est FALSE par défaut dans user_roles et bloqué par CHECK)
SELECT throws_ok(
    $$ INSERT INTO user_roles (user_id, user_is_archived, role_id) VALUES (200, FALSE, 1) $$,
    '23503', -- Foreign Key Violation (car l'user 200 est en is_archived = TRUE)
    NULL,
    'Interdit d''attribuer un rôle à un utilisateur archivé'
);

---
--- 5. TIMESTAMPS
---

SELECT ok(
    updated_at >= created_at,
    'Le timestamp updated_at doit être cohérent'
) FROM roles WHERE name = 'Admin';

SELECT * FROM finish();
ROLLBACK;