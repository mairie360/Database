BEGIN;
SELECT plan(11); -- On ajoute un test pour valider l'insertion des politiques

---
--- 1. PRÉPARATION DES DÉPENDANCES
---
-- On a besoin d'un utilisateur pour les clés étrangères des logs
INSERT INTO users (id, first_name, last_name, email, password, status, is_archived)
VALUES (401, 'Test', 'Retention', 'retention@test.com', 'pwd', 'active', FALSE)
ON CONFLICT DO NOTHING;

---
--- 2. STRUCTURE & CONFIG (5 tests)
---
SELECT has_table('retention_policies');
SELECT has_type('archive_strategy_type');

SELECT is(strategy, 'PARTITION_DROP'::archive_strategy_type, 'access_logs policy is PARTITION_DROP') 
FROM retention_policies WHERE table_name = 'access_logs';
    
SELECT lives_ok(
    $$ INSERT INTO retention_policies (table_name, retention_period, strategy) 
       VALUES ('temp_test', '1 day', 'DELETE') $$, 
    'Insertion d''une politique de test valide'
);

SELECT throws_ok(
    $$ INSERT INTO retention_policies (table_name, retention_period, strategy) 
       VALUES ('users', '1 month', 'PARTITION_DROP') $$, 
    'P0001', -- On vérifie juste que c'est bien une exception utilisateur
    NULL,    -- On ignore le contenu du message
    'Le trigger doit bloquer la table users (vérification par code SQLSTATE)'
);

---
--- 3. TESTS DE CIBLAGE (10 tests)
---

-- A. Sessions (> 6 mois)
-- Correction : pas de colonne 'token', mais 'token_hash'
INSERT INTO sessions (user_id, user_is_archived, token_hash, expires_at, created_at) 
VALUES (401, FALSE, 'old_hash_123', now(), now() - interval '7 months');

SELECT is(
    count(*)::int, 1, 
    'Identification : 1 session obsolète (rétention 6 mois)'
) FROM sessions 
WHERE created_at < now() - (SELECT retention_period FROM retention_policies WHERE table_name = 'sessions');

-- B. Connection Logs (> 1 an)
-- Correction : ajout de 'user_is_archived' et 'action_type' (ENUM)
INSERT INTO connection_logs (user_id, user_is_archived, ip_address, action_type, timestamp)
VALUES (401, FALSE, '127.0.0.1', 'LOGIN', now() - interval '14 months');

SELECT is(
    count(*)::int, 1, 
    'Identification : 1 log de connexion vieux de 14 mois (seuil 1 an)'
) FROM connection_logs 
WHERE timestamp < now() - (SELECT retention_period FROM retention_policies WHERE table_name = 'connection_logs');

-- C. Access Logs (> 3 ans)
INSERT INTO access_logs (user_id, resource_name, action, result, timestamp)
VALUES (401, 'users', 'read', 'GRANTED', now() - interval '4 years');

SELECT ok(
    EXISTS (SELECT 1 FROM access_logs WHERE timestamp < now() - interval '3 years'),
    'Identification : Logs d''accès hors délai de 3 ans trouvés'
);

---
--- 4. DYNAMISME DES POLITIQUES (2 tests)
---
-- On change la règle pour 'access_logs' de 3 ans à 5 ans
UPDATE retention_policies SET retention_period = '5 years' WHERE table_name = 'access_logs';

SELECT is(
    count(*)::int, 0, 
    'Après passage à 5 ans, le log de 4 ans n''est plus ciblé'
) FROM access_logs 
WHERE timestamp < now() - (SELECT retention_period FROM retention_policies WHERE table_name = 'access_logs');

-- On remet à 3 ans pour la cohérence
UPDATE retention_policies SET retention_period = '3 years' WHERE table_name = 'access_logs';

---
--- 5. SÉCURITÉ DE LA TABLE USERS (2 tests)
---
SELECT is(
    count(*)::int, 0,
    'La table users ne doit jamais être présente dans retention_policies'
) FROM retention_policies WHERE table_name = 'users';

-- Vérification que l'user de test est toujours là (pas de DELETE cascade accidentel)
SELECT is(email, 'retention@test.com', 'L''utilisateur test n''a pas été purgé') 
FROM users WHERE id = 401;

SELECT * FROM finish();
ROLLBACK;