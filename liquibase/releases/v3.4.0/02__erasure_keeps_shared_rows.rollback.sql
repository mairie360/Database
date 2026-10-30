DO $$
DECLARE
    v_fk RECORD;
BEGIN
    FOR v_fk IN
        SELECT c.conname, c.conrelid::regclass AS tbl, a.attname
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
        WHERE c.contype = 'f' AND c.confrelid = 'public.users'::regclass AND c.confdeltype = 'a'
          AND (c.conrelid, a.attname) IN (('public.conversations'::regclass, 'direct_user_low'),
                                          ('public.conversations'::regclass, 'direct_user_high'),
                                          ('public.user_courses'::regclass, 'user_id'))
    LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', v_fk.tbl, v_fk.conname);
        EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES users(id) ON DELETE CASCADE',
                       v_fk.tbl, v_fk.conname, v_fk.attname);
    END LOOP;
END;
$$;
