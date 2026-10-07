-- 1. Table des Conversations
CREATE TABLE conversations (
    id SERIAL PRIMARY KEY,
    title VARCHAR(150),
    group_id INT REFERENCES groups(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2. Table de liaison des Membres
CREATE TABLE conversation_members (
    conversation_id INT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_excluded BOOLEAN DEFAULT FALSE NOT NULL,
    joined_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT u_conversation_user UNIQUE (conversation_id, user_id)
);

-- 3. Table des Messages
CREATE TABLE messages (
    id BIGSERIAL PRIMARY KEY,
    conversation_id INT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    owner_id INT REFERENCES users(id) ON DELETE SET NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 4. Table des compteurs de non-lus
CREATE TABLE unread_counters (
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    conversation_id INT REFERENCES conversations(id) ON DELETE CASCADE,
    unread_count INT DEFAULT 0 NOT NULL,
    PRIMARY KEY (user_id, conversation_id)
);

-- 5. Index de performance
CREATE INDEX idx_conv_members_user ON conversation_members(user_id) WHERE is_excluded = FALSE;
CREATE INDEX idx_messages_history ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_conversations_group ON conversations(group_id) WHERE group_id IS NOT NULL;

-- Droits Admin
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Admin' AND res.name = 'conversations'
AND p.action IN ('read_all', 'create', 'update_all', 'delete_all')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Maire
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Maire' AND res.name = 'conversations'
AND p.action IN ('read', 'create', 'update', 'delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Responsable
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Responsable' AND res.name = 'conversations'
AND p.action IN ('read', 'create', 'update', 'delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits User
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'User' AND res.name = 'conversations'
AND p.action IN ('read', 'update', 'delete', 'create')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Droits Guest
INSERT INTO rights (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
JOIN resources res ON p.resource_id = res.id
WHERE r.name = 'Guest' AND res.name = 'conversations'
AND p.action IN ('read')
ON CONFLICT (role_id, permission_id) DO NOTHING;
