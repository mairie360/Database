DROP TABLE IF EXISTS message_group_mentions;
ALTER TABLE messages DROP COLUMN IF EXISTS mentions_everyone;
