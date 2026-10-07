-- Extension des types ENUM existants pour couvrir les états du front.
--
-- PostgreSQL >= 12 autorise ALTER TYPE ... ADD VALUE dans une transaction ; le
-- changeset reste donc transactionnel (rollback propre en cas d'échec). Seule
-- règle : une nouvelle valeur ne peut pas être consommée dans la transaction
-- qui l'ajoute — les CHECK / DEFAULT / données qui s'en servent sont dans les
-- changesets suivants (transactions distinctes). IF NOT EXISTS rend chaque
-- instruction rejouable.

-- project_status : ajout des étapes de tableau kanban.
ALTER TYPE project_status ADD VALUE IF NOT EXISTS 'todo';
ALTER TYPE project_status ADD VALUE IF NOT EXISTS 'review';

-- task_status : ajout de l'état « en révision ».
ALTER TYPE task_status ADD VALUE IF NOT EXISTS 'review';

-- attachment_type : contenus pédagogiques sans fichier physique.
ALTER TYPE attachment_type ADD VALUE IF NOT EXISTS 'link';
ALTER TYPE attachment_type ADD VALUE IF NOT EXISTS 'quiz';
ALTER TYPE attachment_type ADD VALUE IF NOT EXISTS 'audio';
ALTER TYPE attachment_type ADD VALUE IF NOT EXISTS 'other';
