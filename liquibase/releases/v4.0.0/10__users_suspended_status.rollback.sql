-- The previous CHECK refuses 'suspended': the suspended accounts go back to 'offline' (they can
-- sign in again, as before MAIR-904).
UPDATE users SET status = 'offline' WHERE status = 'suspended';
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_status_check;
ALTER TABLE users ADD CONSTRAINT users_status_check
    CHECK (status IN ('active', 'inactive', 'pending', 'offline', 'archived'));
