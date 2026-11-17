-- MAIR-535: fn_set_group_accesses cross-joined the events resource with the read / update / delete permissions
-- of EVERY resource, so each group-owned event got ACL rows pairing the events resource with permissions of
-- other resources. Remove those rows; the correct ones (permission of the events resource) are untouched.
DELETE FROM access_control ac
USING permissions p, resources res
WHERE p.id = ac.permission_id
  AND res.id = ac.resource_id
  AND res.name = 'events'
  AND p.resource_id <> ac.resource_id;
