BEGIN;
-- On passe le plan à 10 tests
SELECT plan(10);

---
--- 1. PRÉPARATION DES DONNÉES (SEED)
---
INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (700, 'Jean', 'Responsable', 'jean.project@mairie.fr', 'pwd'),
    (701, 'Alice', 'Employé', 'alice.project@mairie.fr', 'pwd')
ON CONFLICT (id) DO NOTHING;

---
--- 2. VÉRIFICATION DE LA STRUCTURE DES TABLES (4 tests)
---
SELECT has_table('projects');
SELECT has_table('project_members');
SELECT has_table('tasks');
SELECT has_table('task_history');

---
--- 3. SCÉNARIOS STANDARDS (SOCLE PROJET ET TÂCHES) (2 tests)
---
-- Test 5 : Création d'un projet de référence
INSERT INTO projects (id, title, description, owner_id)
VALUES (1001, 'Modèle Voirie et Infrastructures', 'Template de base pour les travaux.', 700);

SELECT is(
    (SELECT owner_id FROM projects WHERE id = 1001),
    700,
    'Le projet doit être correctement initialisé avec son responsable'
);

-- Test 6 : Attribution d'une tâche et changement de statut
INSERT INTO tasks (id, project_id, title, status, assigned_to)
VALUES (2001, 1001, 'Analyse des sols Place de la Mairie', 'todo', 701);

UPDATE tasks SET status = 'in_progress' WHERE id = 2001;

SELECT ok(
    EXISTS (SELECT 1 FROM task_history WHERE task_id = 2001 AND old_status = 'todo' AND new_status = 'in_progress'),
    'Le trigger doit enregistrer automatiquement les transitions de statut dans task_history'
);

---
--- 4. TESTS DES CHAMPS PERSONNALISÉS (JSONB) (4 tests)
---

-- Préparation : Création d'un projet avec des champs par défaut et d'un projet avec un schéma JSON
INSERT INTO projects (id, title, owner_id)
VALUES (1002, 'Projet sans schema', 700);

INSERT INTO projects (id, title, owner_id, custom_field_schema)
VALUES (1003, 'Projet avec schema', 700, '[{"name": "budget", "type": "number"}, {"name": "urgent", "type": "checkbox"}]'::jsonb);

-- Test 7 : Vérification des valeurs par défaut JSONB (Projets et Tâches)
INSERT INTO tasks (id, project_id, title) VALUES (2002, 1002, 'Tâche standard');

SELECT is(
    (SELECT custom_field_schema::text FROM projects WHERE id = 1002),
    '[]',
    'Par défaut, un projet doit avoir un schema custom_fields initialisé en tableau JSON vide'
);

SELECT is(
    (SELECT custom_fields::text FROM tasks WHERE id = 2002),
    '{}',
    'Par défaut, une tâche doit avoir des custom_fields initialisés en objet JSON vide'
);

-- Test 8 & 9 : Insertion et interrogation dans le JSONB d'une tâche
INSERT INTO tasks (id, project_id, title, custom_fields)
VALUES (2003, 1003, 'Achat des matériaux', '{"budget": 15000, "urgent": true, "options": ["A", "B"]}'::jsonb);

SELECT is(
    -- L'opérateur ->> renvoie la valeur du JSON sous forme de texte
    (SELECT custom_fields->>'budget' FROM tasks WHERE id = 2003),
    '15000',
    'On doit pouvoir extraire la valeur texte d''un champ personnalisé (budget) via l''opérateur JSONB ->>'
);

SELECT is(
    -- On peut caster le résultat de l'opérateur ->> vers le type SQL correspondant
    (SELECT (custom_fields->>'urgent')::boolean FROM tasks WHERE id = 2003),
    true,
    'On doit pouvoir extraire et caster correctement un booléen depuis les custom_fields JSONB'
);

---
--- FIN DES TESTS
---
SELECT * FROM finish();
ROLLBACK;
