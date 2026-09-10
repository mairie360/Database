-- Formations : formateur, métadonnées de catalogue, métadonnées pédagogiques
-- des contenus, notation et progression au niveau contenu.
--
-- Sécurité prod : contraintes sur `courses` / `course_attachments` (tables
-- préexistantes) posées en NOT VALID — appliquées aux écritures futures, sans
-- rescanner l'existant. Le VALIDATE CONSTRAINT est une étape ultérieure.

---
-- courses
---
ALTER TABLE courses ADD COLUMN IF NOT EXISTS instructor_user_id  INTEGER;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS instructor_group_id INTEGER;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS instructor_label    TEXT;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS category            VARCHAR(128);
ALTER TABLE courses ADD COLUMN IF NOT EXISTS level               VARCHAR(16);
ALTER TABLE courses ADD COLUMN IF NOT EXISTS is_mandatory        BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS deadline            DATE;

ALTER TABLE courses DROP CONSTRAINT IF EXISTS fk_courses_instructor_user;
ALTER TABLE courses ADD CONSTRAINT fk_courses_instructor_user
    FOREIGN KEY (instructor_user_id) REFERENCES users(id) ON DELETE SET NULL NOT VALID;

ALTER TABLE courses DROP CONSTRAINT IF EXISTS fk_courses_instructor_group;
ALTER TABLE courses ADD CONSTRAINT fk_courses_instructor_group
    FOREIGN KEY (instructor_group_id) REFERENCES groups(id) ON DELETE RESTRICT NOT VALID;

-- Formateur : au plus une représentation (utilisateur, groupe ou libellé libre).
ALTER TABLE courses DROP CONSTRAINT IF EXISTS chk_courses_instructor_exclusive;
ALTER TABLE courses ADD CONSTRAINT chk_courses_instructor_exclusive
    CHECK (num_nonnulls(instructor_user_id, instructor_group_id, instructor_label) <= 1) NOT VALID;

ALTER TABLE courses DROP CONSTRAINT IF EXISTS chk_courses_level;
ALTER TABLE courses ADD CONSTRAINT chk_courses_level
    CHECK (level IS NULL OR level IN ('beginner', 'intermediate', 'advanced')) NOT VALID;

CREATE INDEX IF NOT EXISTS idx_courses_instructor_user_id  ON courses (instructor_user_id);
CREATE INDEX IF NOT EXISTS idx_courses_instructor_group_id ON courses (instructor_group_id);

---
-- course_attachments : métadonnées pédagogiques + contenus sans fichier
---
ALTER TABLE course_attachments ADD COLUMN IF NOT EXISTS title            VARCHAR(255);
ALTER TABLE course_attachments ADD COLUMN IF NOT EXISTS description      TEXT;
ALTER TABLE course_attachments ADD COLUMN IF NOT EXISTS duration_seconds INTEGER;
ALTER TABLE course_attachments ADD COLUMN IF NOT EXISTS sort_order       INTEGER NOT NULL DEFAULT 1;
ALTER TABLE course_attachments ADD COLUMN IF NOT EXISTS is_required      BOOLEAN NOT NULL DEFAULT TRUE;

-- Reprise : le titre pédagogique reprend le nom de fichier pour l'existant
-- (COALESCE garantit qu'aucune ligne ne bloque le SET NOT NULL).
UPDATE course_attachments SET title = COALESCE(file_name, 'Sans titre') WHERE title IS NULL;
ALTER TABLE course_attachments ALTER COLUMN title SET NOT NULL;

-- Un lien / quiz / contenu interne n'a pas forcément de fichier.
ALTER TABLE course_attachments ALTER COLUMN file_name DROP NOT NULL;
ALTER TABLE course_attachments ALTER COLUMN file_url  DROP NOT NULL;

ALTER TABLE course_attachments DROP CONSTRAINT IF EXISTS chk_course_attachments_duration;
ALTER TABLE course_attachments ADD CONSTRAINT chk_course_attachments_duration
    CHECK (duration_seconds IS NULL OR duration_seconds >= 0) NOT VALID;

ALTER TABLE course_attachments DROP CONSTRAINT IF EXISTS chk_course_attachments_sort_order;
ALTER TABLE course_attachments ADD CONSTRAINT chk_course_attachments_sort_order
    CHECK (sort_order >= 1) NOT VALID;

-- Une URL non vide reste obligatoire pour les contenus basés sur un fichier.
ALTER TABLE course_attachments DROP CONSTRAINT IF EXISTS chk_course_attachments_file_url;
ALTER TABLE course_attachments ADD CONSTRAINT chk_course_attachments_file_url
    CHECK (
        file_type NOT IN ('video', 'pdf', 'document', 'link', 'audio')
        OR (file_url IS NOT NULL AND length(file_url) > 0)
    ) NOT VALID;

---
-- course_ratings : une note par utilisateur et par formation
---
CREATE TABLE IF NOT EXISTS course_ratings (
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    course_id  INTEGER NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    rating     SMALLINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, course_id),
    CONSTRAINT chk_course_ratings_rating CHECK (rating BETWEEN 1 AND 5)
);

CREATE INDEX IF NOT EXISTS idx_course_ratings_course ON course_ratings (course_id);

---
-- user_content_progress : progression au niveau d'un contenu de chapitre
---
CREATE TABLE IF NOT EXISTS user_content_progress (
    user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content_id   INTEGER NOT NULL REFERENCES course_attachments(id) ON DELETE CASCADE,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    completed_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, content_id),
    CONSTRAINT chk_user_content_progress_completed
        CHECK (is_completed = (completed_at IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_user_content_progress_content ON user_content_progress (content_id);
