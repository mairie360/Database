-- Trigger : Historique des tâches
CREATE OR REPLACE FUNCTION fn_log_task_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO task_history (task_id, old_status, new_status)
        VALUES (NEW.id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_after_task_status_update ON tasks;
CREATE TRIGGER tr_after_task_status_update AFTER UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION fn_log_task_status_change();

-- Trigger : Règle métier des champs SELECT
CREATE OR REPLACE FUNCTION fn_validate_custom_field_rules()
RETURNS TRIGGER AS $$
DECLARE
    v_type_champ field_type;
    v_count_options INT;
BEGIN
    SELECT type_champ INTO v_type_champ
    FROM project_field_templates pft
    JOIN task_custom_values tcv ON tcv.template_id = pft.id
    WHERE tcv.id = NEW.custom_value_id;

    SELECT COUNT(*)::INT INTO v_count_options
    FROM task_custom_options
    WHERE custom_value_id = NEW.custom_value_id;

    IF v_type_champ = 'select' AND v_count_options >= 1 THEN
        RAISE EXCEPTION 'Un champ de type SELECT ne peut lier qu''une seule option maximum.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_before_insert_custom_option ON task_custom_options;
CREATE TRIGGER tr_before_insert_custom_option BEFORE INSERT ON task_custom_options FOR EACH ROW EXECUTE FUNCTION fn_validate_custom_field_rules();

-- Fonction : Clonage de projet
CREATE OR REPLACE FUNCTION fn_create_project_with_template(
    p_title VARCHAR(255),
    p_description TEXT,
    p_owner_id INT,
    p_source_project_id INT
) RETURNS INT AS $$
DECLARE
    v_new_project_id INT;
    v_field RECORD;
    v_new_template_id INT;
BEGIN
    INSERT INTO projects (title, description, owner_id, status)
    VALUES (p_title, p_description, p_owner_id, 'active')
    RETURNING id INTO v_new_project_id;

    IF p_source_project_id IS NOT NULL THEN
        FOR v_field IN SELECT id, label, type_champ FROM project_field_templates WHERE project_id = p_source_project_id LOOP
            INSERT INTO project_field_templates (project_id, label, type_champ)
            VALUES (v_new_project_id, v_field.label, v_field.type_champ)
            RETURNING id INTO v_new_template_id;

            IF v_field.type_champ IN ('select', 'checkbox') THEN
                INSERT INTO field_select_options (template_id, option_value, sort_order)
                SELECT v_new_template_id, option_value, sort_order FROM field_select_options WHERE template_id = v_field.id;
            END IF;
        END LOOP;
    END IF;
    RETURN v_new_project_id;
END;
$$ LANGUAGE plpgsql;
