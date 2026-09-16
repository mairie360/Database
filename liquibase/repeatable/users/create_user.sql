-- Point d'entrée unique pour la création d'un utilisateur : le rôle est
-- obligatoire (pas de valeur par défaut) afin d'éviter les créations
-- d'utilisateurs orphelins de tout rôle.
CREATE OR REPLACE FUNCTION create_user(
    p_first_name VARCHAR,
    p_last_name VARCHAR,
    p_email VARCHAR,
    p_password VARCHAR,
    p_role_id INT,
    p_phone_number VARCHAR DEFAULT NULL,
    p_status VARCHAR DEFAULT 'offline'
)
RETURNS INT AS $$
DECLARE
    v_user_id INT;
BEGIN
    IF p_role_id IS NULL THEN
        RAISE EXCEPTION 'Le rôle est obligatoire pour créer un utilisateur.'
        USING ERRCODE = 'not_null_violation';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM roles WHERE id = p_role_id) THEN
        RAISE EXCEPTION 'Le rôle % n''existe pas.', p_role_id
        USING ERRCODE = 'foreign_key_violation';
    END IF;

    INSERT INTO users (first_name, last_name, email, password, phone_number, status)
    VALUES (p_first_name, p_last_name, p_email, p_password, p_phone_number, p_status)
    RETURNING id INTO v_user_id;

    INSERT INTO user_roles (user_id, role_id)
    VALUES (v_user_id, p_role_id);

    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql;
