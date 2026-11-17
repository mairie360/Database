-- MAIR-535: fn_set_group_accesses cross-joined the events resource with the read / update / delete permissions
-- of EVERY resource, so each group-owned event got ACL rows pairing the events resource with permissions of
-- other resources. Remove those rows; the correct ones (permission of the events resource) are untouched.
--
-- The purge is limited to the exact footprint of the old trigger, so nothing else can be deleted: the row must
-- belong to the group that owns the event it points at, and carry a read / update / delete permission of
-- another resource. Rows of any other shape (manual grants, other resources, unknown instances) are kept.
DELETE FROM access_control ac
USING permissions p, resources res, events e
WHERE p.id = ac.permission_id
  AND res.id = ac.resource_id
  AND res.name = 'events'
  AND e.id = ac.resource_instance_id
  AND e.owner_group_id = ac.group_id
  AND p.action IN ('read', 'update', 'delete')
  AND p.resource_id <> ac.resource_id;
