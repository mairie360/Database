BEGIN;
SELECT plan(9); -- Nous programmons 9 tests unitaires

---
--- 1. PRÉPARATION DES DONNÉES (SEED)
---
INSERT INTO users (id, first_name, last_name, email, password)
VALUES (600, 'Charles', 'Formateur', 'charles.elearning@mairie.fr', 'pwd')
ON CONFLICT (id) DO NOTHING;

---
--- 2. VÉRIFICATION DE LA STRUCTURE
---
SELECT has_table('courses');
SELECT has_table('course_modules');
SELECT has_table('course_attachments');
SELECT has_table('user_courses');
SELECT has_table('user_modules');

---
--- 3. SCÉNARIOS FONCTIONNELS
---

-- Insertion d'une formation "Sécurité Données RGPD"
INSERT INTO courses (id, title, description)
VALUES (10, 'Formation RGPD Collectivités', 'Comprendre les enjeux du RGPD en mairie.');

-- Ajout de 2 modules obligatoires
INSERT INTO course_modules (id, course_id, title, sort_order) VALUES
(101, 10, 'Introduction et définitions', 1),
(102, 10, 'Les obligations de la collectivité', 2);

-- Test 1 : Vérification de la liaison du fichier externe (S3 / Stockage hors base)
SELECT lives_ok(
    $$
    INSERT INTO course_attachments (module_id, file_name, file_type, file_url)
    VALUES (101, 'guide_rgpd_mairie.pdf', 'pdf', 'https://s3.mairie360.local/elearning/guides/guide_rgpd_mairie.pdf');
    $$,
    'La base de données doit pouvoir stocker des URLs pointant vers des fichiers stockés en dehors de la DB'
);

-- Test 2 : Validation du premier module par l'utilisateur 600
-- Le trigger doit automatiquement l'inscrire à la formation et passer le statut global à 'in_progress'
SELECT lives_ok(
    $$ INSERT INTO user_modules (user_id, module_id, is_completed) VALUES (600, 101, TRUE); $$,
    'La validation d''un module individuel doit être enregistrée sans erreur'
);

SELECT is(
    (SELECT status FROM user_courses WHERE user_id = 600 AND course_id = 10),
    'in_progress'::progress_status,
    'Le trigger doit passer automatiquement le statut global de la formation à ''in_progress'''
);

-- Test 3 : Validation du DEUXIÈME et DERNIER module (Complétion de la formation)
INSERT INTO user_modules (user_id, module_id, is_completed) VALUES (600, 102, TRUE);

SELECT is(
    (SELECT status FROM user_courses WHERE user_id = 600 AND course_id = 10),
    'completed'::progress_status,
    'Une fois tous les modules complétés, la formation doit basculer au statut ''completed'' de façon automatique'
);

---
--- FIN DES TESTS
---
SELECT * FROM finish();
ROLLBACK;
