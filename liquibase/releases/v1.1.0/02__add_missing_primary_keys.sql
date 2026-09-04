---
-- INTÉGRITÉ / PERFORMANCES : Clés primaires manquantes
--
-- Une table sans PRIMARY KEY ne garantit pas l'unicité de ses lignes et
-- pénalise les mises à jour (pas d'identifiant de ligne stable, réplication
-- logique impossible). Couvre les tables signalées par
-- tests/16_default_bigint.sql (hors tables techniques Liquibase).
---

-- conversation_members : clé naturelle (conversation_id, user_id), déjà unique.
ALTER TABLE conversation_members DROP CONSTRAINT IF EXISTS u_conversation_user;
ALTER TABLE conversation_members
    ADD CONSTRAINT pk_conversation_members PRIMARY KEY (conversation_id, user_id);

-- user_calendar_params : une ligne par utilisateur, user_id déjà unique.
DROP INDEX IF EXISTS idx_user_calendar_params;
ALTER TABLE user_calendar_params DROP CONSTRAINT IF EXISTS user_calendar_params_user_id_key;
ALTER TABLE user_calendar_params
    ADD CONSTRAINT pk_user_calendar_params PRIMARY KEY (user_id);

-- event_members : user_id est nullable (invitations de groupe), pas de clé
-- naturelle NOT NULL -> clé de substitution.
ALTER TABLE event_members ADD COLUMN IF NOT EXISTS id BIGINT GENERATED ALWAYS AS IDENTITY;
ALTER TABLE event_members
    ADD CONSTRAINT pk_event_members PRIMARY KEY (id);

-- recurrence_members : user_id / group_id en XOR (les deux nullables) -> clé
-- de substitution.
ALTER TABLE recurrence_members ADD COLUMN IF NOT EXISTS id BIGINT GENERATED ALWAYS AS IDENTITY;
ALTER TABLE recurrence_members
    ADD CONSTRAINT pk_recurrence_members PRIMARY KEY (id);
