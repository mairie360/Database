-- MAIR-477: trg_users_updated_at ran the same body as tr_10_users_updated_at
-- (users/fn_refresh_updated_at.sql) on every UPDATE of users. This changeset is
-- runOnChange, so the new content drops it on every existing database.
DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
