-- Irreversible by design (MAIR-535): the purged rows paired a permission with the wrong resource and must
-- never come back. Rolling the release back leaves them deleted.
SELECT 1;
