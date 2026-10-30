-- Irreversible by design (MAIR-286): the purged passwords and photos are not kept anywhere, and
-- must never come back into users_audit_log. Rolling the release back leaves the rows purged.
SELECT 1;
