-- Welcome tour: whether the agent finished or skipped the onboarding shown on the Dashboard.
-- Nullable, NULL means "not done yet". No backfill: existing accounts see the tour once.
ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN;
