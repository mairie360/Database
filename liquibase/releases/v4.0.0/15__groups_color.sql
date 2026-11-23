-- Colour of a group (MAIR-923 F18): a name of the palette of the charter (the module colours of
-- lib-components, each with a light and a dark value), NULL = neutral. Expand only.
ALTER TABLE groups ADD COLUMN color TEXT;
ALTER TABLE groups ADD CONSTRAINT chk_groups_color
    CHECK (color IS NULL OR color IN ('blue', 'teal', 'green', 'orange', 'purple', 'pink', 'neutral'));
