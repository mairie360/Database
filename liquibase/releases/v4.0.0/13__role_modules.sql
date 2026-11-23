-- Modules a role opens (MAIR-916, epic MAIR-824): the administration ticks, for each role, the
-- modules of the navigation its agents reach. The ids are the entries of the shared navigation of
-- lib-components. Expand only: a new table, filled for the existing roles with what they reach today
-- (every module, Administration for the Admin role only).
CREATE TABLE role_modules (
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    module TEXT NOT NULL,
    PRIMARY KEY (role_id, module),
    CONSTRAINT chk_role_modules_module
        CHECK (module IN ('dashboard', 'projects', 'calendar', 'messages', 'training', 'admin', 'settings'))
);

INSERT INTO role_modules (role_id, module)
SELECT r.id, m.module
FROM roles r
CROSS JOIN (VALUES ('dashboard'), ('projects'), ('calendar'), ('messages'), ('training'), ('admin'), ('settings')) AS m(module)
WHERE m.module <> 'admin' OR r.name = 'Admin'
ON CONFLICT DO NOTHING;
