-- Archived accounts are anonymized one year after their archiving by default (MAIR-289). The mairie
-- sets its own period with `UPDATE retention_policies SET retention_period = '<interval>' WHERE
-- table_name = 'users'` (Deploiment configuration, MAIR-294); fn_apply_retention_policies() reads it.
INSERT INTO retention_policies (table_name, retention_period, strategy)
VALUES ('users', '1 year', 'ANONYMIZE')
ON CONFLICT (table_name) DO NOTHING;
