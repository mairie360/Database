# Purges of personal data

Records of the one-off purges the schema applies to data that should never have been kept
(epic MAIR-284). Each instance applies a purge when it migrates to the release that ships it: the
date is `DATEEXECUTED` of the changeset in its `databasechangelog` table, and the Liquibase job log
holds the number of rows purged. Give both to the mairie for its processing record (GDPR art. 30)
and, if a personal data breach is assessed, to its DPO.

```sql
SELECT id, dateexecuted FROM databasechangelog WHERE id LIKE 'mair-286-%';
```

## `mair-286-01`: passwords and photos in `users_audit_log` (MAIR-286)

- **Release**: the first one that ships `liquibase/releases/v3.0.1/03__purge_audit_log_secrets.sql`.
- **What was kept**: until MAIR-286, every write to `users` copied the whole row into
  `users_audit_log` (`previous_data` / `new_data`), retained 10 years and append-only. This
  included the password hash, the **plaintext password** of the accounts created before MAIR-169
  (their migration to argon2id was an `UPDATE`, whose `previous_data` kept the plaintext), and the
  photo.
- **Scope of the purge**: the keys `password` and `photo` are removed from `previous_data` and
  `new_data` of every row of `users_audit_log`. The rest of each row (who, when, which action, the
  other columns) is kept. The append-only guard is disabled for this statement only.
- **Irreversible**: the release rollback leaves the rows purged; no copy is kept.
- **From then on**: `fn_audit_and_mutate_user()` leaves out the columns marked `audit_log: false`
  in `gdpr/inventory.yaml`, checked by `tests/36_gdpr_schema_test.sql`.
- **Exposure before the purge**: `users_audit_log` is readable by no API role (MAIR-114), only by
  the database owner and its backups. Backups taken before the purge still hold the values until
  they expire.
