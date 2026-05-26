-- 1. Table des Conversations (Le Salon de Chat)
CREATE TABLE conversations (
    id SERIAL PRIMARY KEY,
    title VARCHAR(150),                               -- Optionnel (ex: vide pour un chat à deux, rempli pour un projet)
    group_id INT REFERENCES groups(id) ON DELETE CASCADE, -- Si lié à un service/groupe entier (Accès dynamique)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Table de liaison des Membres (Gestion fine des accès)
CREATE TABLE conversation_members (
    id SERIAL PRIMARY KEY,
    conversation_id INT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Le point crucial pour "retirer" quelqu'un d'un groupe ou d'un chat global
    is_excluded BOOLEAN DEFAULT FALSE NOT NULL,

    -- Tracing (Optionnel mais recommandé pour savoir quand l'accès a changé)
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Contrainte d'unicité : un utilisateur n'a qu'une seule ligne d'état par conversation
    CONSTRAINT u_conversation_user UNIQUE (conversation_id, user_id)
);

-- 3. Table des Messages (L'historique des échanges)
CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    conversation_id INT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id INT REFERENCES users(id) ON DELETE SET NULL, -- SET NULL évite de supprimer les messages si un agent part
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Index de performance (Critère page 6 : performance et instantanéité)
-- Optimise l'affichage de la liste des conversations d'un utilisateur
CREATE INDEX idx_conv_members_user ON conversation_members(user_id) WHERE is_excluded = FALSE;

-- Optimise le chargement ultra-rapide de l'historique des messages par ordre chronologique
CREATE INDEX idx_messages_history ON messages(conversation_id, created_at DESC);

-- Optimise la recherche de chat lié à un service municipal spécifique
CREATE INDEX idx_conversations_group ON conversations(group_id) WHERE group_id IS NOT NULL;

CREATE TABLE unread_counters (
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    conversation_id INT REFERENCES conversations(id) ON DELETE CASCADE,
    unread_count INT DEFAULT 0 NOT NULL,
    PRIMARY KEY (user_id, conversation_id)
);

-- ============================================================================
-- TRIGGER 1 : INCRÉMENTATION AUTOMATIQUE À L'INSERTION D'UN MESSAGE
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_auto_increment_unread_counter()
RETURNS TRIGGER AS $$
DECLARE
    v_group_id INT;
BEGIN
    -- 1. On vérifie si la conversation est liée à un groupe
    SELECT group_id INTO v_group_id 
    FROM conversations 
    WHERE id = NEW.conversation_id;

    IF v_group_id IS NOT NULL THEN
        -- CAS A : Chat de groupe. On incrémente pour tous les membres du groupe (via group_users)
        -- en excluant l'expéditeur et les personnes bannies de ce chat dans conversation_members
        INSERT INTO unread_counters (conversation_id, user_id, unread_count)
        SELECT NEW.conversation_id, gu.user_id, 1
        FROM group_users gu
        WHERE gu.group_id = v_group_id
          AND gu.user_id != NEW.sender_id
          AND gu.user_id NOT IN (
              SELECT user_id FROM conversation_members 
              WHERE conversation_id = NEW.conversation_id AND is_excluded = TRUE
          )
        ON CONFLICT (conversation_id, user_id) 
        DO UPDATE SET unread_count = unread_counters.unread_count + 1;

    ELSE
        -- CAS B : Chat privé (multi-users). On incrémente pour tous les membres inscrits
        -- en excluant l'expéditeur et les exclus
        INSERT INTO unread_counters (conversation_id, user_id, unread_count)
        SELECT NEW.conversation_id, cm.user_id, 1
        FROM conversation_members cm
        WHERE cm.conversation_id = NEW.conversation_id 
          AND cm.user_id != NEW.sender_id 
          AND cm.is_excluded = FALSE
        ON CONFLICT (conversation_id, user_id) 
        DO UPDATE SET unread_count = unread_counters.unread_count + 1;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_after_message_insert
    AFTER INSERT ON messages
    FOR EACH ROW 
    EXECUTE FUNCTION fn_auto_increment_unread_counter();


-- ============================================================================
-- TRIGGER 2 : NETTOYAGE (DELETE) DE LA LIGNE SI LE COMPTEUR TOMBE À 0
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_clean_empty_unread_counter()
RETURNS TRIGGER AS $$
BEGIN
    -- Si le compteur est mis à jour à 0 (ou moins), on supprime la ligne
    IF NEW.unread_count <= 0 THEN
        DELETE FROM unread_counters 
        WHERE conversation_id = NEW.conversation_id AND user_id = NEW.user_id;
        RETURN NULL; -- Annule l'update puisque la ligne est supprimée
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_before_unread_update
    BEFORE UPDATE ON unread_counters
    FOR EACH ROW 
    EXECUTE FUNCTION fn_clean_empty_unread_counter();
