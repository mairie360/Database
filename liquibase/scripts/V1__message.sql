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
