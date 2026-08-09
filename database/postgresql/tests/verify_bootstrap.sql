-- BL-MVP-010 - verificacion reproducible del bootstrap PostgreSQL 18.
DO $verify$
DECLARE
    v_role_count integer;
    v_extension_count integer;
    v_public_create_count integer;
    v_search_path_count integer;
BEGIN
    SELECT count(*)
    INTO v_role_count
    FROM pg_catalog.pg_roles
    WHERE rolname IN (
        'jp_owner',
        'jp_migrator',
        'jp_app',
        'jp_backoffice',
        'jp_worker',
        'jp_readonly'
    );

    IF v_role_count <> 6 THEN
        RAISE EXCEPTION
            'Bootstrap invalido: se esperaban 6 roles y existen %.',
            v_role_count;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname IN (
            'jp_owner',
            'jp_migrator',
            'jp_app',
            'jp_backoffice',
            'jp_worker',
            'jp_readonly'
        )
          AND (
              rolcanlogin
              OR rolsuper
              OR rolcreatedb
              OR rolcreaterole
              OR rolreplication
              OR rolbypassrls
          )
    ) THEN
        RAISE EXCEPTION
            'Bootstrap invalido: los roles base deben ser NOLOGIN y sin privilegios administrativos.';
    END IF;

    IF NOT pg_has_role('jp_migrator', 'jp_owner', 'MEMBER') THEN
        RAISE EXCEPTION
            'Bootstrap invalido: jp_migrator debe ser miembro de jp_owner.';
    END IF;

    SELECT count(*)
    INTO v_extension_count
    FROM pg_catalog.pg_extension e
    JOIN pg_catalog.pg_namespace n
      ON n.oid = e.extnamespace
    WHERE e.extname IN ('pg_trgm', 'btree_gist')
      AND n.nspname = 'public';

    IF v_extension_count <> 2 THEN
        RAISE EXCEPTION
            'Bootstrap invalido: pg_trgm y btree_gist deben existir en public.';
    END IF;

    SELECT count(*)
    INTO v_public_create_count
    FROM pg_catalog.pg_namespace n
    CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(
            n.nspacl,
            pg_catalog.acldefault('n', n.nspowner)
        )
    ) acl
    WHERE n.nspname = 'public'
      AND acl.grantee = 0
      AND acl.privilege_type = 'CREATE';

    IF v_public_create_count <> 0 THEN
        RAISE EXCEPTION
            'Bootstrap invalido: PUBLIC conserva CREATE sobre el esquema public.';
    END IF;

    SELECT count(*)
    INTO v_search_path_count
    FROM pg_catalog.pg_roles
    WHERE rolname IN (
        'jp_app',
        'jp_backoffice',
        'jp_worker',
        'jp_readonly'
    )
      AND rolconfig @> ARRAY['search_path=pg_catalog, public'];

    IF v_search_path_count <> 4 THEN
        RAISE EXCEPTION
            'Bootstrap invalido: search_path seguro no esta configurado en los cuatro roles de runtime.';
    END IF;
END;
$verify$;

SELECT
    'OK: bootstrap PostgreSQL BL-MVP-010 verificado.' AS result;
