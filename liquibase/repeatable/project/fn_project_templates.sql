-- Triggers: a project is created from a template (MAIR-566).
--
-- BEFORE INSERT on projects: no template_id means the default template; an empty
-- custom_field_schema takes the template's one. AFTER INSERT: the template's statuses are
-- copied into the project (project_task_statuses), so editing a template never changes an
-- existing project. The default template cannot be deleted.
CREATE OR REPLACE FUNCTION fn_set_project_template()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.template_id IS NULL THEN
        NEW.template_id := (SELECT id FROM project_templates WHERE is_default);
    END IF;
    IF NEW.custom_field_schema IS NULL OR NEW.custom_field_schema = '[]'::JSONB THEN
        NEW.custom_field_schema := COALESCE(
            (SELECT custom_field_schema FROM project_templates WHERE id = NEW.template_id),
            '[]'::JSONB);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS tr_before_project_template ON projects;
CREATE TRIGGER tr_before_project_template
    BEFORE INSERT ON projects
    FOR EACH ROW EXECUTE FUNCTION fn_set_project_template();

CREATE OR REPLACE FUNCTION fn_copy_template_statuses()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO project_task_statuses (project_id, name, color, category, position)
    SELECT NEW.id, name, color, category, position
    FROM project_template_statuses
    WHERE template_id = NEW.template_id
    ORDER BY position;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS tr_after_project_copy_statuses ON projects;
CREATE TRIGGER tr_after_project_copy_statuses
    AFTER INSERT ON projects
    FOR EACH ROW EXECUTE FUNCTION fn_copy_template_statuses();

CREATE OR REPLACE FUNCTION fn_protect_default_template()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.is_default THEN
        RAISE EXCEPTION 'the default project template cannot be deleted'
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS tr_before_project_template_delete ON project_templates;
CREATE TRIGGER tr_before_project_template_delete
    BEFORE DELETE ON project_templates
    FOR EACH ROW EXECUTE FUNCTION fn_protect_default_template();
