-- MAIR-904: an administrator can suspend an account and reactivate it later. A suspended account
-- keeps every row (roles, groups, factors), cannot sign in nor use a JWT, and is not an
-- administrator, like an archived one; unlike archiving it is reversible without restore_user().
-- Expand only: the CHECK accepts one more value, every value it accepted before stays valid.
-- Added NOT VALID (no scan under the ACCESS EXCLUSIVE lock), validated by the next changeset
-- (mair-904-02), which only takes a SHARE UPDATE EXCLUSIVE lock.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_status_check;
ALTER TABLE users ADD CONSTRAINT users_status_check
    CHECK (status IN ('active', 'inactive', 'pending', 'offline', 'archived', 'suspended')) NOT VALID;
