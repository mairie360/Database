-- Postgres cannot drop an enum value: the rollback leaves `ANONYMIZE` in archive_strategy_type,
-- unused once the policy row of the next changeset is rolled back.
SELECT 1;
