-- 1. Ajout de la nouvelle colonne
ALTER TABLE users
ADD COLUMN first_connect BOOLEAN NOT NULL DEFAULT TRUE;

-- 2. Mise à jour des données existantes (ex: pour l'Admin par défaut)
UPDATE users
SET first_connect = FALSE
WHERE id = 1;
