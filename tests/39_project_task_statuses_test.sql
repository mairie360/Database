BEGIN;
SELECT plan(24);

-- MAIR-566 (releases/v3.1.0): task statuses set per project, copied from a project template.

-- SQLSTATE raised by `p_sql`, 'ok' when it succeeds.
CREATE FUNCTION pg_temp.sqlstate_of(p_sql TEXT) RETURNS TEXT AS $$
BEGIN
    EXECUTE p_sql;
    RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
    RETURN SQLSTATE;
END;
$$ LANGUAGE plpgsql;

-- Deferred checks run at the commit: SET CONSTRAINTS ALL IMMEDIATE runs them now.
CREATE FUNCTION pg_temp.sqlstate_at_commit(p_sql TEXT) RETURNS TEXT AS $$
BEGIN
    EXECUTE p_sql;
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
    RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
    SET CONSTRAINTS ALL DEFERRED;
    RETURN SQLSTATE;
END;
$$ LANGUAGE plpgsql;

INSERT INTO users (id, first_name, last_name, email, password, status, is_archived)
VALUES (95660, 'Status', 'Owner', 'status.owner@example.com',
        '$argon2id$v=19$m=16,t=2,p=1$dGVzdHNhbHQ$dGVzdGhhc2g', 'active', FALSE);

-- 1. Templates provided from the start.
SELECT results_eq(
    $$SELECT t.name::TEXT, string_agg(s.name || ':' || s.category, ', ' ORDER BY s.position)
      FROM project_templates t JOIN project_template_statuses s ON s.template_id = t.id
      WHERE t.name IN ('Simple', 'Avec validation', 'Marché public', 'Événement')
      GROUP BY t.id, t.name ORDER BY t.id$$,
    $$VALUES
        ('Simple', 'À faire:todo, En cours:in_progress, Terminé:completed'),
        ('Avec validation', 'À faire:todo, En cours:in_progress, À valider:in_progress, Validé:completed'),
        ('Marché public', 'Étude:todo, Appel d''offres:in_progress, Attribution:in_progress, Exécution:in_progress, Réception:completed'),
        ('Événement', 'Préparation:todo, Communication:in_progress, Jour J:in_progress, Bilan:completed')$$,
    'The four templates are provided with their statuses'
);
SELECT is(
    (SELECT name::TEXT FROM project_templates WHERE is_default), 'Simple',
    'Simple is the default template'
);

-- 2. A project created from a template gets a copy of its statuses.
INSERT INTO projects (id, title, owner_id, template_id)
VALUES (95661, 'Marché de la voirie', 95660, (SELECT id FROM project_templates WHERE name = 'Marché public'));
SELECT results_eq(
    $$SELECT name::TEXT, category::TEXT, position FROM project_task_statuses WHERE project_id = 95661 ORDER BY position$$,
    $$VALUES ('Étude', 'todo', 0), ('Appel d''offres', 'in_progress', 1), ('Attribution', 'in_progress', 2),
             ('Exécution', 'in_progress', 3), ('Réception', 'completed', 4)$$,
    'A project created from a template gets a copy of its statuses'
);

INSERT INTO projects (id, title, owner_id) VALUES (95662, 'Sans modèle', 95660);
SELECT is(
    (SELECT template_id FROM projects WHERE id = 95662), (SELECT id FROM project_templates WHERE is_default),
    'A project created without a template uses the default one'
);
SELECT is(
    (SELECT string_agg(name, ', ' ORDER BY position) FROM project_task_statuses WHERE project_id = 95662),
    'À faire, En cours, Terminé',
    'and gets its statuses'
);

-- Editing the template afterwards does not change the project.
UPDATE project_template_statuses SET name = 'Analyse'
WHERE template_id = (SELECT id FROM project_templates WHERE name = 'Marché public') AND position = 0;
SELECT is(
    (SELECT name::TEXT FROM project_task_statuses WHERE project_id = 95661 AND position = 0), 'Étude',
    'Editing a template does not change the projects created from it'
);

-- Custom fields of the template are copied into an empty schema.
INSERT INTO project_templates (id, name, custom_field_schema)
VALUES (95660, 'Modèle avec champs', '[{"label": "Budget", "task_type": "select"}]');
INSERT INTO project_template_statuses (template_id, name, category, position) VALUES
    (95660, 'Ouvert', 'todo', 0), (95660, 'Actif', 'in_progress', 1), (95660, 'Clos', 'completed', 2);
INSERT INTO projects (id, title, owner_id, template_id) VALUES (95663, 'Avec champs', 95660, 95660);
SELECT is(
    (SELECT custom_field_schema FROM projects WHERE id = 95663),
    '[{"label": "Budget", "task_type": "select"}]'::JSONB,
    'A project takes the custom fields of its template'
);

-- 3. Tasks point to a status of their own project; the category follows.
INSERT INTO tasks (id, project_id, title, status_id)
VALUES (95661, 95661, 'Rédiger le cahier des charges',
        (SELECT id FROM project_task_statuses WHERE project_id = 95661 AND name = 'Attribution'));
SELECT is(
    (SELECT status::TEXT FROM tasks WHERE id = 95661), 'in_progress',
    'A task takes the category of its status'
);

UPDATE tasks SET status_id = (SELECT id FROM project_task_statuses WHERE project_id = 95661 AND name = 'Réception')
WHERE id = 95661;
SELECT ok(
    (SELECT status = 'completed' AND archived_at IS NOT NULL FROM tasks WHERE id = 95661),
    'A task moved to a completed status is completed and archived'
);

SELECT is(
    pg_temp.sqlstate_of($$INSERT INTO tasks (project_id, title, status_id)
        VALUES (95661, 'Mauvais projet', (SELECT id FROM project_task_statuses WHERE project_id = 95662 AND position = 0))$$),
    '23503',
    'A task cannot use the status of another project'
);

-- A writer giving the category alone (older than MAIR-566) gets the first status of it.
INSERT INTO tasks (id, project_id, title, status) VALUES (95662, 95661, 'Publier l''avis', 'in_progress');
SELECT is(
    (SELECT s.name::TEXT FROM tasks t JOIN project_task_statuses s ON s.id = t.status_id WHERE t.id = 95662),
    'Appel d''offres',
    'A task written with its category alone takes the first status of that category'
);
INSERT INTO tasks (id, project_id, title, status) VALUES (95663, 95661, 'En revue', 'review');
SELECT is(
    (SELECT status::TEXT FROM tasks WHERE id = 95663), 'in_progress',
    'review is read as in progress'
);
UPDATE tasks SET status_id = (SELECT id FROM project_task_statuses WHERE project_id = 95661 AND name = 'Exécution')
WHERE id = 95662;
UPDATE tasks SET title = 'Publier l''avis au BOAMP', status = 'in_progress' WHERE id = 95662;
SELECT is(
    (SELECT s.name::TEXT FROM tasks t JOIN project_task_statuses s ON s.id = t.status_id WHERE t.id = 95662),
    'Exécution',
    'Writing the category the task already has keeps its status'
);
UPDATE tasks SET status = 'todo' WHERE id = 95662;
SELECT is(
    (SELECT s.name::TEXT FROM tasks t JOIN project_task_statuses s ON s.id = t.status_id WHERE t.id = 95662),
    'Étude',
    'Writing another category moves the task to the first status of it'
);

-- A move between two statuses of the same category is in the history.
UPDATE tasks SET status_id = (SELECT id FROM project_task_statuses WHERE project_id = 95661 AND name = 'Attribution')
WHERE id = 95663;
SELECT is(
    (SELECT changes->'status_name' FROM task_history WHERE task_id = 95663 AND action = 'status_changed'
     ORDER BY id DESC LIMIT 1),
    '{"from": "Appel d''offres", "to": "Attribution"}'::JSONB,
    'A move between statuses of the same category is logged with their names'
);

-- 4. Statuses of a project stay usable.
SELECT is(
    pg_temp.sqlstate_of($$DELETE FROM project_task_statuses WHERE project_id = 95661 AND name = 'Exécution'$$),
    'ok',
    'A status without tasks can be deleted'
);
SELECT is(
    pg_temp.sqlstate_of($$DELETE FROM project_task_statuses WHERE project_id = 95661 AND name = 'Attribution'$$),
    '23001',
    'A status holding tasks cannot be deleted before its tasks are moved'
);
SELECT is(
    pg_temp.sqlstate_at_commit($$DELETE FROM project_task_statuses WHERE project_id = 95662 AND category = 'completed'$$),
    '23514',
    'A project cannot lose its last completed status'
);
-- Replacing the last status of a category within the transaction is allowed.
SELECT is(
    pg_temp.sqlstate_at_commit($$
        INSERT INTO project_task_statuses (project_id, name, category, position) VALUES (95662, 'Fait', 'completed', 3);
        DELETE FROM project_task_statuses WHERE project_id = 95662 AND name = 'Terminé'$$),
    'ok',
    'The last status of a category can be replaced by another one'
);
SELECT is(
    pg_temp.sqlstate_at_commit($$
        UPDATE project_task_statuses SET position = CASE position WHEN 0 THEN 1 ELSE 0 END
        WHERE project_id = 95662 AND position IN (0, 1)$$),
    'ok',
    'Statuses can be reordered by swapping positions'
);
SELECT is(
    pg_temp.sqlstate_of($$INSERT INTO project_task_statuses (project_id, name, category, position)
        VALUES (95662, 'en cours', 'in_progress', 9)$$),
    '23505',
    'Two statuses of a project cannot have the same name, whatever the case'
);

-- Changing the category of a status moves its tasks.
UPDATE project_task_statuses SET category = 'completed' WHERE project_id = 95661 AND name = 'Attribution';
SELECT is(
    (SELECT status::TEXT FROM tasks WHERE id = 95663), 'completed',
    'Changing the category of a status moves its tasks to that category'
);

-- 5. Templates.
SELECT is(
    pg_temp.sqlstate_of($$DELETE FROM project_templates WHERE is_default$$),
    '23001',
    'The default template cannot be deleted'
);
DELETE FROM project_templates WHERE id = 95660;
SELECT is(
    (SELECT template_id FROM projects WHERE id = 95663), NULL,
    'Deleting a template keeps the projects created from it'
);

SELECT * FROM finish();
ROLLBACK;
