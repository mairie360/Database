BEGIN;
SELECT plan(10);

-- MAIR-1228: trigram indexes of the global search (releases/v4.1.0). Each business API matches
-- `<column> ILIKE '%term%'`: the plain column must carry a gin_trgm_ops index, or every search
-- reads the whole table.

CREATE FUNCTION pg_temp.plan_of(p_sql TEXT) RETURNS TEXT AS $$
DECLARE
    v_line TEXT;
    v_plan TEXT := '';
BEGIN
    FOR v_line IN EXECUTE 'EXPLAIN (COSTS OFF) ' || p_sql LOOP
        v_plan := v_plan || v_line || E'\n';
    END LOOP;
    RETURN v_plan;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.is_trgm(p_table TEXT, p_index TEXT, p_column TEXT) RETURNS BOOLEAN AS $$
    SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = p_table AND indexname = p_index
                   AND indexdef LIKE '%gin (' || p_column || ' gin_trgm_ops)%');
$$ LANGUAGE sql;

SELECT ok(pg_temp.is_trgm('projects', 'idx_projects_title_trgm', 'title'), 'projects.title is trigram indexed');
SELECT ok(pg_temp.is_trgm('projects', 'idx_projects_description_trgm', 'description'), 'projects.description is trigram indexed');
SELECT ok(pg_temp.is_trgm('tasks', 'idx_tasks_title_trgm', 'title'), 'tasks.title is trigram indexed');
SELECT ok(pg_temp.is_trgm('events', 'idx_events_name_trgm', 'name'), 'events.name is trigram indexed');
SELECT ok(pg_temp.is_trgm('conversations', 'idx_conversations_title_trgm', 'title'), 'conversations.title is trigram indexed');
SELECT ok(pg_temp.is_trgm('messages', 'idx_messages_content_trgm', 'content'), 'messages.content is trigram indexed');
SELECT ok(pg_temp.is_trgm('courses', 'idx_courses_title_trgm', 'title'), 'courses.title is trigram indexed');

-- Sequential scans are disabled so the plan does not depend on the size of the test data.
SET LOCAL enable_seqscan = off;

SELECT alike(
    pg_temp.plan_of($$ SELECT id FROM projects WHERE title ILIKE '%' || 'voirie' || '%' $$),
    '%idx_projects_title_trgm%',
    'A project search uses idx_projects_title_trgm'
);
SELECT alike(
    pg_temp.plan_of($$ SELECT id FROM messages WHERE content ILIKE '%conseil municipal%' $$),
    '%idx_messages_content_trgm%',
    'A message search uses idx_messages_content_trgm'
);
SELECT alike(
    pg_temp.plan_of($$ SELECT id FROM events WHERE name ILIKE '%réunion%' $$),
    '%idx_events_name_trgm%',
    'An event search uses idx_events_name_trgm'
);

SELECT * FROM finish();
ROLLBACK;
