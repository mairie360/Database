-- liquibase formatted sql

-- changeset developpement:1-project-enums
CREATE TYPE project_status AS ENUM ('active', 'suspended', 'completed');
CREATE TYPE task_status AS ENUM ('todo', 'in_progress', 'completed');
CREATE TYPE task_priority AS ENUM ('low', 'medium', 'high');
CREATE TYPE field_type AS ENUM ('date', 'checkbox', 'select');
-- rollback DROP TYPE field_type;
-- rollback DROP TYPE task_priority;
-- rollback DROP TYPE task_status;
-- rollback DROP TYPE project_status;

-- changeset developpement:2-projects-table
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status project_status DEFAULT 'active' NOT NULL,
    owner_id INT REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- rollback DROP TABLE projects;

-- changeset developpement:3-project-members-table
CREATE TABLE project_members (
    project_id INT REFERENCES projects(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (project_id, user_id)
);
-- rollback DROP TABLE project_members;

-- changeset developpement:4-tasks-table
CREATE TABLE tasks (
    id SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    status task_status DEFAULT 'todo' NOT NULL,
    priority task_priority DEFAULT 'medium' NOT NULL,
    due_date TIMESTAMP,
    assigned_to INT REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- rollback DROP TABLE tasks;

-- changeset developpement:5-task-history-table
CREATE TABLE task_history (
    id SERIAL PRIMARY KEY,
    task_id INT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    changed_by INT REFERENCES users(id) ON DELETE SET NULL,
    old_status task_status,
    new_status task_status,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- rollback DROP TABLE task_history;

-- changeset developpement:6-project-field-templates-table
CREATE TABLE project_field_templates (
    id SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    label VARCHAR(100) NOT NULL,
    type_champ field_type NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- rollback DROP TABLE project_field_templates;

-- changeset developpement:7-field-select-options-table
CREATE TABLE field_select_options (
    id SERIAL PRIMARY KEY,
    template_id INT NOT NULL REFERENCES project_field_templates(id) ON DELETE CASCADE,
    option_value VARCHAR(100) NOT NULL,
    sort_order INT DEFAULT 1
);
-- rollback DROP TABLE field_select_options;

-- changeset developpement:8-task-custom-values-table
CREATE TABLE task_custom_values (
    id SERIAL PRIMARY KEY,
    task_id INT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    template_id INT NOT NULL REFERENCES project_field_templates(id) ON DELETE CASCADE,
    value_date TIMESTAMP DEFAULT NULL,
    value_text TEXT DEFAULT NULL,
    CONSTRAINT u_task_field UNIQUE (task_id, template_id)
);
-- rollback DROP TABLE task_custom_values;

-- changeset developpement:9-task-custom-options-table
CREATE TABLE task_custom_options (
    custom_value_id INT NOT NULL REFERENCES task_custom_values(id) ON DELETE CASCADE,
    option_id INT NOT NULL REFERENCES field_select_options(id) ON DELETE CASCADE,
    PRIMARY KEY (custom_value_id, option_id)
);
-- rollback DROP TABLE task_custom_options;

-- changeset developpement:10-triggers-and-functions splitStatements:false
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

CREATE TRIGGER tr_after_task_status_update
    AFTER UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION fn_log_task_status_change();

CREATE OR REPLACE FUNCTION fn_validate_custom_field_rules()
RETURNS TRIGGER AS $$
DECLARE
    v_type_champ field_type;
    v_count_options INT;
BEGIN -- CORRECTION : Enlèvement de END_DECLARATION;
    SELECT type_champ INTO v_type_champ
    FROM project_field_templates pft
    JOIN task_custom_values tcv ON tcv.template_id = pft.id
    WHERE tcv.id = NEW.custom_value_id;

    SELECT COUNT(*)::INT INTO v_count_options
    FROM task_custom_options
    WHERE custom_value_id = NEW.custom_value_id;

    IF v_type_champ = 'select' AND v_count_options >= 1 THEN
        RAISE EXCEPTION 'Un champ de type SELECT ne peut lier qu''une seule option maximum à la tâche.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_before_insert_custom_option
    BEFORE INSERT ON task_custom_options
    FOR EACH ROW
    EXECUTE FUNCTION fn_validate_custom_field_rules();

CREATE OR REPLACE FUNCTION fn_create_project_with_template(
    p_title VARCHAR(255),
    p_description TEXT,
    p_owner_id INT,
    p_source_project_id INT
)
RETURNS INT AS $$
DECLARE
    v_new_project_id INT;
    v_field RECORD;
    v_new_template_id INT;
BEGIN
    INSERT INTO projects (title, description, owner_id, status)
    VALUES (p_title, p_description, p_owner_id, 'active')
    RETURNING id INTO v_new_project_id;

    IF p_source_project_id IS NOT NULL THEN
        FOR v_field IN
            SELECT id, label, type_champ
            FROM project_field_templates
            WHERE project_id = p_source_project_id
        LOOP
            INSERT INTO project_field_templates (project_id, label, type_champ)
            VALUES (v_new_project_id, v_field.label, v_field.type_champ)
            RETURNING id INTO v_new_template_id;

            IF v_field.type_champ IN ('select', 'checkbox') THEN
                INSERT INTO field_select_options (template_id, option_value, sort_order)
                SELECT v_new_template_id, option_value, sort_order
                FROM field_select_options
                WHERE template_id = v_field.id;
            END IF;
        END LOOP;
    END IF;

    RETURN v_new_project_id;
END;
$$ LANGUAGE plpgsql;
-- rollback DROP FUNCTION fn_create_project_with_template(VARCHAR, TEXT, INT, INT);
-- rollback DROP TRIGGER tr_before_insert_custom_option ON task_custom_options;
-- rollback DROP FUNCTION fn_validate_custom_field_rules();
-- rollback DROP TRIGGER tr_after_task_status_update ON tasks;
-- rollback DROP FUNCTION fn_log_task_status_change();
