-- Rollback of 01__direct_conversations.sql (MAIR-478). The pair columns are
-- dropped and kind goes back to the v1.2.0 rule (direct unless a group is
-- set). Merged duplicates stay merged, and the hidden rows given back to
-- participants who had left stay (an excluded member sees nothing).
ALTER TABLE conversations
    DROP CONSTRAINT IF EXISTS uq_conversations_direct_pair,
    DROP CONSTRAINT IF EXISTS chk_conversations_direct_pair;
DROP INDEX IF EXISTS idx_conversations_direct_user_high;

UPDATE conversations
SET kind = CASE WHEN group_id IS NOT NULL THEN 'group' ELSE 'direct' END;

ALTER TABLE conversations
    DROP COLUMN IF EXISTS direct_user_low,
    DROP COLUMN IF EXISTS direct_user_high;
