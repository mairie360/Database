ALTER TABLE connection_logs DROP CONSTRAINT connection_logs_user_id_fkey;

ALTER TABLE connection_logs
  ADD CONSTRAINT connection_logs_user_id_fkey
  FOREIGN KEY (user_id, user_is_archived)
  REFERENCES users(id, is_archived)
  ON DELETE CASCADE
  ON UPDATE CASCADE;

  CREATE OR REPLACE FUNCTION delete_user(p_user_id INT)
  RETURNS void AS $$
  BEGIN
      -- 1. Vérifier si l'utilisateur existe et n'est pas déjà archivé
      IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND is_archived = FALSE) THEN
          RAISE EXCEPTION 'L''utilisateur avec l''ID % n''existe pas ou est déjà archivé.', p_user_id;
      END IF;

      -- =========================================================================
      -- 2. SUPPRESSIONS MANUELLES (Ce qui ne doit pas être archivé)
      -- On doit supprimer ces données AVANT d'archiver l'utilisateur pour ne pas
      -- violer les contraintes CHECK(user_is_archived = FALSE).
      -- =========================================================================

      -- Déconnexion et droits d'accès
      DELETE FROM sessions WHERE user_id = p_user_id;
      DELETE FROM user_roles WHERE user_id = p_user_id;

      -- Retrait des groupes, projets et événements (Participations actives)
      DELETE FROM group_users WHERE user_id = p_user_id;
      DELETE FROM project_members WHERE user_id = p_user_id;
      DELETE FROM event_members WHERE user_id = p_user_id;

      -- Retrait des espaces de messagerie et compteurs
      DELETE FROM conversation_members WHERE user_id = p_user_id;
      DELETE FROM unread_counters WHERE user_id = p_user_id;

      -- Retrait du suivi des formations en cours/complétées
      DELETE FROM user_courses WHERE user_id = p_user_id;
      DELETE FROM user_modules WHERE user_id = p_user_id;

      -- =========================================================================
      -- 3. GESTION DE LA PROPRIÉTÉ DIRECTE
      -- Supprime les entités dont il était l'unique propriétaire.
      -- (La "vraie" cascade PostgreSQL gèrera alors les tâches, messages liés, etc.)
      -- =========================================================================
      DELETE FROM projects WHERE owner_id = p_user_id;
      DELETE FROM groups WHERE owner_id = p_user_id;

      -- =========================================================================
      -- 4. DÉSASSIGNATION (Simule le ON DELETE SET NULL)
      -- Libère les tâches qui lui étaient affectées.
      -- =========================================================================
      UPDATE tasks SET assigned_to = NULL WHERE assigned_to = p_user_id;

      -- =========================================================================
      -- 5. L'ARCHIVAGE FINAL
      -- Tout le reste (task_history, messages envoyés, events créés, connection_logs, audit)
      -- est conservé intact car rattaché à son "id" d'origine.
      -- =========================================================================
      UPDATE users
      SET is_archived = TRUE,
          status = 'archived',
          updated_at = now()
      WHERE id = p_user_id;

  END;
  $$ LANGUAGE plpgsql;
