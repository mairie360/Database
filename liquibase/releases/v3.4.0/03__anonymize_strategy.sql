-- Retention strategy of the archived accounts (MAIR-289): `ANONYMIZE` runs anonymize_user() on the
-- accounts archived for longer than the period of their policy (next changeset). An enum value
-- cannot be used in the transaction that adds it: the policy row is a changeset of its own.
ALTER TYPE archive_strategy_type ADD VALUE IF NOT EXISTS 'ANONYMIZE';
