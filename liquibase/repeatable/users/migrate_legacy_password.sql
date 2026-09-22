-- MAIR-169: rewrites a legacy plaintext users.password with its argon2id
-- hash. Postgres has no argon2id implementation (pgcrypto only covers
-- bcrypt/md5/sha family digests), so hashing happens outside the database:
-- the caller is either the login path, on a successful plaintext compare, or
-- a one-off admin script run over the accounts that never reconnect. Either
-- way this function only ever accepts a value that already looks like an
-- argon2id PHC hash, so it cannot be used to write a plaintext password back
-- into the column, and it is a no-op once the stored value already looks
-- hashed, so a slow admin script can't race a user's own login and clobber a
-- fresher hash with a stale one.
CREATE OR REPLACE FUNCTION migrate_legacy_password(p_user_id INT, p_password_hash VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE
    v_row_count INT;
BEGIN
    IF p_password_hash !~ '^\$argon2id\$v=\d+\$m=\d+,t=\d+,p=\d+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$' THEN
        RAISE EXCEPTION 'p_password_hash is not an argon2id hash.'
        USING ERRCODE = 'invalid_parameter_value';
    END IF;

    UPDATE users
    SET password = p_password_hash
    WHERE id = p_user_id
      AND password !~ '^\$argon2id\$v=\d+\$m=\d+,t=\d+,p=\d+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$';

    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RETURN v_row_count > 0;
END;
$$ LANGUAGE plpgsql;
