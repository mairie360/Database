BEGIN;
SELECT plan(63);

---
--- PRÉPARATION DES DONNÉES (SEED)
---
INSERT INTO users (id, first_name, last_name, email, password)
VALUES
    (8801, 'Ada',  'Test', 'ada.v120@test.fr',  'pwd'),
    (8802, 'Bob',  'Test', 'bob.v120@test.fr',  'pwd'),
    (8803, 'Cléo', 'Test', 'cleo.v120@test.fr', 'pwd')
ON CONFLICT (id) DO NOTHING;

INSERT INTO groups (id, name, owner_id) VALUES (8810, 'Service Test v120', 8801)
ON CONFLICT (id) DO NOTHING;

INSERT INTO courses (id, title) VALUES (8820, 'Formation Test v120')
ON CONFLICT (id) DO NOTHING;
INSERT INTO course_modules (id, course_id, title) VALUES (8821, 8820, 'Chapitre 1')
ON CONFLICT (id) DO NOTHING;
INSERT INTO course_attachments (id, module_id, title, file_name, file_type, file_url)
VALUES (8830, 8821, 'Contenu seed', 'seed.pdf', 'pdf', 'https://x.test/seed.pdf')
ON CONFLICT (id) DO NOTHING;

INSERT INTO projects (id, title, owner_id) VALUES (8840, 'Projet Test v120', 8801)
ON CONFLICT (id) DO NOTHING;
INSERT INTO tasks (id, project_id, title) VALUES (8841, 8840, 'Tâche Test v120')
ON CONFLICT (id) DO NOTHING;

INSERT INTO conversations (id, title, group_id, kind)
VALUES (8850, 'Conv Test v120', 8810, 'group') ON CONFLICT (id) DO NOTHING;
INSERT INTO messages (id, conversation_id, owner_id, content)
VALUES (8851, 8850, 8801, 'seed') ON CONFLICT (id) DO NOTHING;

INSERT INTO recurrence_rules (id, type_recurrence, start_date, start_time, duration, owner_id)
VALUES (8860, 'weekly', now(), '09:00:00', interval '1 hour', 8801)
ON CONFLICT (id) DO NOTHING;

---
--- 1. Utilisateurs et préférences
---
SELECT has_column('users', 'biography', 'users.biography ajoutée');
SELECT has_table('user_preferences', 'table user_preferences créée');
SELECT has_table('user_notification_settings', 'table user_notification_settings créée');
SELECT col_is_pk('user_preferences', 'user_id', 'user_preferences : PK sur user_id');
SELECT throws_ok(
    $$ INSERT INTO user_preferences (user_id, theme) VALUES (8801, 'bleu') $$,
    NULL, NULL, 'user_preferences.theme contraint à light/dark/system');
SELECT lives_ok(
    $$ INSERT INTO user_preferences (user_id, theme, font_size) VALUES (8802, 'dark', 14) $$,
    'user_preferences : une ligne valide est acceptée');

---
--- 2. Types ENUM étendus
---
SELECT ok('todo'   = ANY(enum_range(NULL::project_status)::text[]), 'project_status contient todo');
SELECT ok('review' = ANY(enum_range(NULL::project_status)::text[]), 'project_status contient review');
SELECT ok('review' = ANY(enum_range(NULL::task_status)::text[]),    'task_status contient review');
SELECT ok(
    ARRAY['link', 'quiz', 'audio', 'other'] <@ enum_range(NULL::attachment_type)::text[],
    'attachment_type contient link/quiz/audio/other');

---
--- 3. Calendrier
---
SELECT has_column('events', 'category', 'events.category ajoutée');
SELECT has_column('events', 'service_group_id', 'events.service_group_id ajoutée');
SELECT has_column('events', 'service_label', 'events.service_label ajoutée');
SELECT has_column('events', 'location', 'events.location ajoutée');
SELECT throws_ok(
    $$ INSERT INTO events (name, start_date, end_date, owner_id, service_group_id, service_label)
       VALUES ('E', now(), now() + interval '1 hour', 8801, 8810, 'Libellé') $$,
    NULL, NULL, 'events : service_group_id et service_label mutuellement exclusifs');
SELECT throws_ok(
    $$ INSERT INTO events (name, start_date, end_date, owner_id, category)
       VALUES ('E', now(), now() + interval '1 hour', 8801, 'soiree') $$,
    NULL, NULL, 'events.category contraint à la liste fermée');
SELECT has_column('recurrence_rules', 'days_of_week', 'recurrence_rules.days_of_week ajoutée');
SELECT col_not_null('recurrence_rules', 'intervalle', 'recurrence_rules.intervalle NOT NULL');
SELECT throws_ok(
    $$ UPDATE recurrence_rules SET days_of_week = '{9}' WHERE id = 8860 $$,
    NULL, NULL, 'days_of_week rejette une valeur hors 0..6');
SELECT lives_ok(
    $$ UPDATE recurrence_rules SET days_of_week = '{1,3,5}' WHERE id = 8860 $$,
    'days_of_week accepte lundi/mercredi/vendredi');

---
--- 4. Projets et tâches
---
SELECT has_column('projects', 'responsible_id', 'projects.responsible_id ajoutée');
SELECT has_column('projects', 'priority', 'projects.priority ajoutée');
SELECT has_column('projects', 'due_date', 'projects.due_date ajoutée');
SELECT has_column('projects', 'labels', 'projects.labels ajoutée');
SELECT throws_ok(
    $$ INSERT INTO projects (title, owner_id, labels) VALUES ('P', 8801, ARRAY['a', '']::text[]) $$,
    NULL, NULL, 'projects.labels rejette une étiquette vide');
SELECT lives_ok(
    $$ INSERT INTO projects (title, owner_id, responsible_id, priority, due_date, labels)
       VALUES ('P', 8801, 8802, 'high', CURRENT_DATE, ARRAY['voirie', 'urgent']::text[]) $$,
    'projects : responsable / priorité / échéance / labels acceptés');
SELECT has_table('task_assignees', 'table task_assignees créée');
SELECT col_is_pk('task_assignees', ARRAY['task_id', 'user_id'], 'task_assignees : PK (task_id, user_id)');
SELECT lives_ok(
    $$ INSERT INTO task_assignees (task_id, user_id) VALUES (8841, 8802), (8841, 8803) $$,
    'task_assignees : plusieurs personnes sur une tâche');
SELECT is(
    (SELECT count(*)::integer FROM task_assignees WHERE task_id = 8841),
    2, 'task_assignees : les deux affectations sont présentes');
SELECT throws_ok(
    $$ INSERT INTO task_assignees (task_id, user_id) VALUES (8841, 8802) $$,
    NULL, NULL, 'task_assignees : pas de doublon (task_id, user_id)');

---
--- 5. Formations
---
SELECT has_column('courses', 'instructor_user_id', 'courses.instructor_user_id ajoutée');
SELECT has_column('courses', 'category', 'courses.category ajoutée');
SELECT has_column('courses', 'level', 'courses.level ajoutée');
SELECT has_column('courses', 'is_mandatory', 'courses.is_mandatory ajoutée');
SELECT has_column('courses', 'deadline', 'courses.deadline ajoutée');
SELECT throws_ok(
    $$ INSERT INTO courses (title, instructor_user_id, instructor_label) VALUES ('C', 8801, 'Externe') $$,
    NULL, NULL, 'courses : formateur unique (user XOR group XOR label)');
SELECT throws_ok(
    $$ INSERT INTO courses (title, level) VALUES ('C', 'expert') $$,
    NULL, NULL, 'courses.level contraint à beginner/intermediate/advanced');
SELECT has_column('course_attachments', 'title', 'course_attachments.title ajoutée');
SELECT has_column('course_attachments', 'duration_seconds', 'course_attachments.duration_seconds ajoutée');
SELECT has_column('course_attachments', 'sort_order', 'course_attachments.sort_order ajoutée');
SELECT has_column('course_attachments', 'is_required', 'course_attachments.is_required ajoutée');
SELECT col_is_null('course_attachments', 'file_name', 'course_attachments.file_name devient facultative');
SELECT lives_ok(
    $$ INSERT INTO course_attachments (module_id, file_type, file_url, title)
       VALUES (8821, 'quiz', NULL, 'Quiz 1') $$,
    'course_attachments : un quiz sans fichier est accepté');
SELECT throws_ok(
    $$ INSERT INTO course_attachments (module_id, file_type, file_url, title)
       VALUES (8821, 'video', NULL, 'Vidéo 1') $$,
    NULL, NULL, 'course_attachments : une vidéo exige une URL');
SELECT has_table('course_ratings', 'table course_ratings créée');
SELECT throws_ok(
    $$ INSERT INTO course_ratings (user_id, course_id, rating) VALUES (8801, 8820, 6) $$,
    NULL, NULL, 'course_ratings.rating borné à 1..5');
SELECT lives_ok(
    $$ INSERT INTO course_ratings (user_id, course_id, rating) VALUES (8801, 8820, 4) $$,
    'course_ratings : une note valide est acceptée');
SELECT has_trigger('course_ratings', 'trg_course_ratings_updated_at', 'course_ratings : trigger updated_at');
SELECT has_table('user_content_progress', 'table user_content_progress créée');
SELECT throws_ok(
    $$ INSERT INTO user_content_progress (user_id, content_id, is_completed)
       VALUES (8802, 8830, true) $$,
    NULL, NULL, 'user_content_progress : is_completed impose completed_at');
SELECT lives_ok(
    $$ INSERT INTO user_content_progress (user_id, content_id, is_completed, completed_at)
       VALUES (8802, 8830, true, now()) $$,
    'user_content_progress : contenu terminé avec date acceptée');

---
--- 6. Messagerie
---
SELECT has_column('conversations', 'kind', 'conversations.kind ajoutée');
SELECT col_not_null('conversations', 'kind', 'conversations.kind NOT NULL');
SELECT throws_ok(
    $$ INSERT INTO conversations (title, kind) VALUES ('X', 'canal') $$,
    NULL, NULL, 'conversations.kind contraint à direct/group');
SELECT lives_ok(
    $$ INSERT INTO conversations (title, kind) VALUES ('X', 'direct') $$,
    'conversations : une conversation directe est acceptée');
SELECT has_table('message_mentions', 'table message_mentions créée');
SELECT lives_ok(
    $$ INSERT INTO message_mentions (message_id, user_id) VALUES (8851, 8802) $$,
    'message_mentions : mention d''un utilisateur');
SELECT has_table('message_business_links', 'table message_business_links créée');
SELECT throws_ok(
    $$ INSERT INTO message_business_links (message_id) VALUES (8851) $$,
    NULL, NULL, 'message_business_links : exactement une cible (0 refusée)');
SELECT throws_ok(
    $$ INSERT INTO message_business_links (message_id, project_id, task_id) VALUES (8851, 8840, 8841) $$,
    NULL, NULL, 'message_business_links : exactement une cible (2 refusées)');
SELECT lives_ok(
    $$ INSERT INTO message_business_links (message_id, project_id) VALUES (8851, 8840) $$,
    'message_business_links : une cible unique est acceptée');
SELECT throws_ok(
    $$ INSERT INTO message_business_links (message_id, project_id) VALUES (8851, 8840) $$,
    NULL, NULL, 'message_business_links : pas de double liaison même cible');

SELECT * FROM finish();
ROLLBACK;
