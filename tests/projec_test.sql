BEGIN;
SELECT plan(15); -- Nous avons bien 15 tests au total

---
--- 1. PRÉPARATION DES DONNÉES (SEED)
---

-- Création des utilisateurs requis sans la colonne 'role' pour éviter le conflit structurel
INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (700, 'Jean', 'Responsable', 'jean.project@mairie.fr', 'pwd'),
    (701, 'Alice', 'Employé', 'alice.project@mairie.fr', 'pwd')
ON CONFLICT (id) DO NOTHING;

---
--- 2. VÉRIFICATION DE LA STRUCTURE DES TABLES (8 tests)
---
SELECT has_table('projects');
SELECT has_table('project_members');
SELECT has_table('tasks');
SELECT has_table('task_history');
SELECT has_table('project_field_templates');
SELECT has_table('field_select_options');
SELECT has_table('task_custom_values');
SELECT has_table('task_custom_options');

---
--- 3. SCÉNARIOS STANDARDS (SOCLE PROJET ET TÂCHES)
---

-- Test 9 : Création d'un projet de référence
INSERT INTO projects (id, title, description, owner_id)
VALUES (1001, 'Modèle Voirie et Infrastructures', 'Template de base pour les travaux.', 700);

SELECT is(
    (SELECT owner_id FROM projects WHERE id = 1001),
    700,
    'Le projet doit être correctement initialisé avec son responsable'
);

-- Test 10 : Attribution d'une tâche et changement de statut (Validation Trigger d'historique)
INSERT INTO tasks (id, project_id, title, status, assigned_to)
VALUES (2001, 1001, 'Analyse des sols Place de la Mairie', 'todo', 701);

UPDATE tasks SET status = 'in_progress' WHERE id = 2001;

SELECT ok(
    EXISTS (SELECT 1 FROM task_history WHERE task_id = 2001 AND old_status = 'todo' AND new_status = 'in_progress'),
    'Le trigger doit enregistrer automatiquement les transitions de statut dans task_history'
);

---
--- 4. SCÉNARIOS MODULAIRES (TEMPLATES ET CHAMPS PERSONNALISÉS)
---

-- Configuration du template sur le projet modèle (1001)
INSERT INTO project_field_templates (id, project_id, label, type_champ) VALUES
(50, 1001, 'Priorité Politique', 'select'),
(51, 1001, 'Quartiers Impactés', 'checkbox');

-- Options pour la liste déroulante (select)
INSERT INTO field_select_options (id, template_id, option_value) VALUES
(10, 50, 'Haute'),
(11, 50, 'Basse');

-- Options pour les cases à cocher (checkbox)
INSERT INTO field_select_options (id, template_id, option_value) VALUES
(20, 51, 'Centre-Ville'),
(21, 51, 'Quartier Nord');

-- Test 11 : Insertion de choix multiples valides sur une tâche (Type Checkbox)
INSERT INTO task_custom_values (id, task_id, template_id) VALUES (3001, 2001, 51);

SELECT lives_ok(
    $$
    INSERT INTO task_custom_options (custom_value_id, option_id) VALUES (3001, 20);
    INSERT INTO task_custom_options (custom_value_id, option_id) VALUES (3001, 21);
    $$,
    'Un champ personnalisé de type CHECKBOX doit accepter de lier plusieurs options à la fois'
);

-- Test 12 : Sécurité du choix unique (Type Select)
INSERT INTO task_custom_values (id, task_id, template_id) VALUES (3002, 2001, 50);
INSERT INTO task_custom_options (custom_value_id, option_id) VALUES (3002, 10);

SELECT throws_ok(
    $$ INSERT INTO task_custom_options (custom_value_id, option_id) VALUES (3002, 11) $$,
    'P0001',
    NULL,
    'Le trigger doit bloquer l''ajout d''une seconde option si le champ est de type SELECT'
);

---
--- 5. SCÉNARIO FONCTION : DUPLICATION DE PROJET AVEC TEMPLATE
---

-- Test 13 : Exécution de la fonction de création par copie de template
SELECT lives_ok(
    $$ SELECT fn_create_project_with_template('Travaux Boulevard République', 'Rénovation complète', 700, 1001); $$,
    'La fonction fn_create_project_with_template doit s''exécuter sans erreur'
);

-- Test 14 : Vérification que les champs du gabarit ont été clonés (Utilisation d'une sous-requête au lieu du DO)
SELECT is(
    (SELECT count(*)::INT
     FROM project_field_templates
     WHERE project_id = (SELECT id FROM projects WHERE title = 'Travaux Boulevard République')),
    2,
    'Le nouveau projet doit hériter des 2 templates de champs personnalisés du modèle'
);

-- Test 15 : Vérification que les options de liste ont également été clonées
SELECT is(
    (SELECT count(*)::INT
     FROM field_select_options fso
     JOIN project_field_templates pft ON fso.template_id = pft.id
     WHERE pft.project_id = (SELECT id FROM projects WHERE title = 'Travaux Boulevard République')),
    4,
    'Le nouveau projet doit cloner l''intégralité des options de sélection (4 au total)'
);

---
--- FIN DES TESTS
---
SELECT * FROM finish();
ROLLBACK;
