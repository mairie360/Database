CREATE OR REPLACE VIEW v_securable_events AS
SELECT
    u.*,
    (SELECT id FROM resources WHERE name = 'events') as resource_id
FROM events u;
