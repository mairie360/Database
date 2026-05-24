-- Enums pour sécuriser les statuts d'avancement
CREATE TYPE progress_status AS ENUM ('not_started', 'in_progress', 'completed');
CREATE TYPE attachment_type AS ENUM ('video', 'pdf', 'document');

-- 1. Table des Formations
CREATE TABLE courses (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Table des Modules / Chapitres (Découpage de la formation)
CREATE TABLE course_modules (
    id SERIAL PRIMARY KEY,
    course_id INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content TEXT,                                     -- Texte ou consignes du module
    sort_order INT DEFAULT 1,                         -- Pour ordonner les chapitres (1, 2, 3...)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Table des Fichiers Externes (F17 / Stockage hors DB)
CREATE TABLE course_attachments (
    id SERIAL PRIMARY KEY,
    module_id INT NOT NULL REFERENCES course_modules(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    file_type attachment_type NOT NULL,
    file_url TEXT NOT NULL,                           -- Ex: 'https://s3.cloud.com/mairie360/formations/guide.pdf'
    file_size_bytes BIGINT,                           -- Utile pour afficher la taille avant téléchargement
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Suivi global de la Formation par Utilisateur
CREATE TABLE user_courses (
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    course_id INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    status progress_status DEFAULT 'not_started' NOT NULL,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    PRIMARY KEY (user_id, course_id)
);

-- 5. Suivi précis par Module (Pour calculer le % d'avancement)
CREATE TABLE user_modules (
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    module_id INT NOT NULL REFERENCES course_modules(id) ON DELETE CASCADE,
    is_completed BOOLEAN DEFAULT FALSE NOT NULL,
    completed_at TIMESTAMP,
    PRIMARY KEY (user_id, module_id)
);

-- 6. Index de performance (Pour générer rapidement les statistiques d'avancement)
CREATE INDEX idx_user_courses_status ON user_courses(user_id, status);
CREATE INDEX idx_user_modules_lookup ON user_modules(user_id, is_completed);

CREATE OR REPLACE FUNCTION fn_update_user_course_progress()
RETURNS TRIGGER AS $$
DECLARE
    v_course_id INT;
    v_total_modules INT;
    v_completed_modules INT;
BEGIN
    -- Retrouver la formation parente du module qui vient d'être validé
    SELECT course_id INTO v_course_id FROM course_modules WHERE id = NEW.module_id;

    -- S'assurer que la ligne d'initialisation existe dans user_courses
    -- CORRECTION : Remplacement de user_counters par user_courses
    INSERT INTO user_courses (user_id, course_id, status, started_at)
    VALUES (NEW.user_id, v_course_id, 'in_progress', CURRENT_TIMESTAMP)
    ON CONFLICT (user_id, course_id)
    DO UPDATE SET status = 'in_progress' WHERE user_courses.status = 'not_started';

    -- Compter le nombre total de modules dans cette formation
    SELECT COUNT(*)::INT INTO v_total_modules FROM course_modules WHERE course_id = v_course_id;

    -- Compter combien de modules cet utilisateur a validé pour cette formation
    SELECT COUNT(*)::INT INTO v_completed_modules
    FROM user_modules um
    JOIN course_modules cm ON um.module_id = cm.id
    WHERE um.user_id = NEW.user_id AND cm.course_id = v_course_id AND um.is_completed = TRUE;

    -- Si l'utilisateur a tout terminé, on met à jour le statut global
    IF v_total_modules = v_completed_modules THEN
        UPDATE user_courses
        SET status = 'completed', completed_at = CURRENT_TIMESTAMP
        WHERE user_id = NEW.user_id AND course_id = v_course_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_after_user_module_update
    AFTER INSERT OR UPDATE ON user_modules
    FOR EACH ROW
    EXECUTE FUNCTION fn_update_user_course_progress();
