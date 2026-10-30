-- MAIR-564: a user holds one role. The JWT carries a single `role` claim (MAIR-529) and
-- Core_API replaces the role on every grant, but nothing stopped a second row: accounts
-- registered with the default Guest role (tr_users_default_role_guest) then given a role
-- by an administrator held both ("Guest, User").
--
-- Each account keeps its lowest role id, the role its JWT already carries since MAIR-529
-- (Admin > Maire > Responsable > User > Guest for the base roles), so nobody's effective
-- role changes. The dropped rows are listed in a NOTICE; the rollback does not bring them
-- back.
DO $$
DECLARE
    v_dropped TEXT;
BEGIN
    SELECT string_agg(format('user %s keeps role %s, drops %s', user_id, role_ids[1], role_ids[2:]),
                      '; ' ORDER BY user_id)
    INTO v_dropped
    FROM (
        SELECT user_id, array_agg(role_id ORDER BY role_id) AS role_ids
        FROM user_roles
        GROUP BY user_id
        HAVING count(*) > 1
    ) multi;

    IF v_dropped IS NOT NULL THEN
        RAISE NOTICE 'MAIR-564: one role per user: %', v_dropped;
    END IF;
END;
$$;

DELETE FROM user_roles ur
WHERE EXISTS (
    SELECT 1 FROM user_roles kept
    WHERE kept.user_id = ur.user_id AND kept.role_id < ur.role_id
);

-- The user is the key: a second role is a unique violation (23505). The former key
-- (user_id, role_id) is implied; idx_user_roles_role still serves the role foreign key.
ALTER TABLE user_roles DROP CONSTRAINT user_roles_pkey;
ALTER TABLE user_roles ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id);
