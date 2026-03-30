BEGIN;
SELECT plan(11);

---
--- 1. PRÉPARATION DES DONNÉES
---
-- Ajout de la ressource manquante si nécessaire
INSERT INTO resources (name) VALUES ('groups') ON CONFLICT DO NOTHING;

-- Création d'utilisateurs de test
INSERT INTO users (id, first_name, last_name, email, password, status)
VALUES 
    (300, 'Jean', 'Owner', 'owner@test.com', 'pwd', 'active'),
    (301, 'Paul', 'Member', 'member@test.com', 'pwd', 'active');

---
--- 2. STRUCTURE & TRIGGERS
---
SELECT has_table('groups');
SELECT has_table('group_users');
SELECT has_trigger('groups', 'trigger_add_owner_as_member');

-- Test du trigger automatique d'adhésion de l'owner
INSERT INTO groups (id, owner_id, name, description)
VALUES (1, 300, 'Groupe Alpha', 'Premier groupe de test');

SELECT ok(
    EXISTS (SELECT 1 FROM group_users WHERE group_id = 1 AND user_id = 300),
    'L''owner doit être automatiquement ajouté aux membres du groupe via trigger'
);

---
--- 3. GESTION DES MEMBRES
---
-- Ajout d'un membre manuellement
INSERT INTO group_users (group_id, user_id) VALUES (1, 301);

SELECT is(
    (SELECT count(*)::INT FROM group_users WHERE group_id = 1),
    2,
    'Le groupe Alpha doit avoir 2 membres'
);

---
--- 4. SÉCURITÉ & ARCHIVAGE (LE POINT CRUCIAL)
---

-- Test : Empêcher l'archivage d'un owner (FK ON DELETE RESTRICT)
-- Ton schéma utilise ON DELETE RESTRICT sur fk_groups_owner
SELECT throws_ok(
    $$ UPDATE users SET is_archived = TRUE WHERE id = 300 $$,
    '23503', -- Foreign key violation
    NULL,
    'On ne peut pas archiver un utilisateur qui possède encore un groupe (RESTRICT)'
);

-- Test : Suppression en cascade des membres lors de l'archivage
-- Pour Paul (membre simple), la FK est ON DELETE CASCADE.
-- On simule d'abord le trigger de nettoyage nécessaire pour Paul
CREATE OR REPLACE FUNCTION fn_cleanup_group_members_on_archive()
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.is_archived = FALSE AND NEW.is_archived = TRUE) THEN
        DELETE FROM group_users WHERE user_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_cleanup_group_members
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_cleanup_group_members_on_archive();

-- On archive le membre Paul
SELECT lives_ok(
    $$ UPDATE users SET is_archived = TRUE, status = 'archived' WHERE id = 301 $$,
    'L''archivage d''un membre simple doit être possible'
);

SELECT is(
    (SELECT count(*)::INT FROM group_users WHERE group_id = 1),
    1,
    'Paul doit avoir été retiré du groupe automatiquement après archivage'
);

---
--- 5. PERMISSIONS & VUES
---
SELECT has_view('v_securable_groups');

SELECT is(
    (SELECT resource_id FROM v_securable_groups WHERE id = 1),
    (SELECT id FROM resources WHERE name = 'groups'),
    'La vue v_securable_groups doit injecter le bon resource_id'
);

-- Vérification des droits Admin sur les groupes
SELECT ok(
    EXISTS (
        SELECT 1 FROM rights ri
        JOIN roles ro ON ri.role_id = ro.id
        JOIN permissions p ON ri.permission_id = p.id
        JOIN resources res ON p.resource_id = res.id
        WHERE ro.name = 'Admin' AND res.name = 'groups' AND p.action = 'delete_all'
    ),
    'L''Admin doit avoir le droit delete_all sur les groupes'
);

SELECT * FROM finish();
ROLLBACK;