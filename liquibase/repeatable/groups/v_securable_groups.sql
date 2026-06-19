CREATE OR REPLACE VIEW v_securable_groups AS
SELECT
    g.*,
    (SELECT id FROM resources WHERE name = 'groups') as resource_id
FROM groups g;
