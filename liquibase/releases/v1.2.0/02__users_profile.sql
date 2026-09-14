-- Profil utilisateur : la fiche front affiche une biographie libre.
-- (Le schéma cible conserve identité, téléphone et photo dans `users` ;
-- aucun champ « service principal » n'est ajouté, cf. groupes existants.)

ALTER TABLE users ADD COLUMN IF NOT EXISTS biography TEXT;
