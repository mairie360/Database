BEGIN;
SELECT plan(10); -- Nombre de tests prévus

-- 1. Préparation : Créer un utilisateur de test
INSERT INTO users (id, first_name, last_name, email, password, status)
VALUES (99, 'Jean', 'Test', 'jean.test@example.com', 'hash_pw', 'active');

---
--- TESTS DE STRUCTURE
---

SELECT has_table('sessions');
SELECT has_trigger('sessions', 'trigger_set_expiration');
SELECT has_trigger('sessions', 'trigger_log_login');

---
--- TESTS DE LOGIQUE FONCTIONNELLE
---

-- 2. Test de l'expiration automatique (7 jours par défaut via session_settings)
INSERT INTO sessions (user_id, token_hash, device_info, ip_address)
VALUES (99, 'token_123', 'Firefox/Linux', '192.168.1.1');

SELECT ok(
    expires_at > now() + interval '6 days' AND expires_at <= now() + interval '7 days',
    'La date d''expiration doit être initialisée à 7 jours par défaut'
) FROM sessions WHERE token_hash = 'token_123';

-- 3. Test du trigger de login (connection_logs)
SELECT is(
    (SELECT action_type FROM connection_logs WHERE user_id = 99 LIMIT 1),
    'LOGIN'::session_action,
    'Un log de type LOGIN doit être créé automatiquement à l''insertion d''une session'
);

-- 4. Test de la vue v_sessions (is_active)
SELECT ok(
    is_active = TRUE,
    'La session fraîchement créée doit être marquée comme active'
) FROM v_sessions WHERE token_hash = 'token_123';

-- 5. Test de la fonction is_session_valid
SELECT ok(
    (SELECT valid FROM is_session_valid('token_123', 'Firefox/Linux')),
    'La fonction is_session_valid doit valider un token correct et actif'
);

-- 6. Test de révocation (LOGOUT)
UPDATE sessions SET revoked_at = now() WHERE token_hash = 'token_123';

SELECT ok(
    is_active = FALSE,
    'Une session révoquée ne doit plus être active dans v_sessions'
) FROM v_sessions WHERE token_hash = 'token_123';

---
--- TESTS DE SÉCURITÉ ET CONTRAINTES
---

-- 7. Test de la FK composite (user_id, user_is_archived)
-- On utilise le code '23503' qui correspond à foreign_key_violation
SELECT throws_ok(
    $$ INSERT INTO sessions (user_id, user_is_archived, token_hash) VALUES (999, FALSE, 'bad_token') $$,
    '23503',
    NULL, -- On ignore le message texte pour éviter les problèmes de matching
    'On ne peut pas créer de session pour un user_id inexistant (FK Violation)'
);

-- 8. Test du trigger de suppression (LOGOUT/CLEANUP dans logs)
DELETE FROM sessions WHERE token_hash = 'token_123';
SELECT ok(
    EXISTS (SELECT 1 FROM connection_logs WHERE user_id = 99 AND action_type = 'LOGOUT'),
    'La suppression d''une session révoquée doit générer un log de type LOGOUT'
);

SELECT * FROM finish();
ROLLBACK;