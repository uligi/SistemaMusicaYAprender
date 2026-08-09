DO $verify$
DECLARE
    login_name text;
    functional_name text;
    expected_memberships integer;
    actual_count integer;
BEGIN
    FOREACH login_name IN ARRAY ARRAY[
        'jp_login_migrator',
        'jp_login_api',
        'jp_login_backoffice',
        'jp_login_worker',
        'jp_login_readonly'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_roles
            WHERE rolname = login_name
              AND rolcanlogin
              AND NOT rolsuper
              AND NOT rolcreatedb
              AND NOT rolcreaterole
              AND NOT rolreplication
              AND NOT rolbypassrls
        ) THEN
            RAISE EXCEPTION 'Identidad LOGIN % ausente o con atributos excesivos.', login_name;
        END IF;
    END LOOP;

    FOREACH functional_name IN ARRAY ARRAY[
        'jp_owner',
        'jp_migrator',
        'jp_app',
        'jp_backoffice',
        'jp_worker',
        'jp_readonly'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_roles
            WHERE rolname = functional_name
              AND NOT rolcanlogin
              AND NOT rolsuper
              AND NOT rolcreatedb
              AND NOT rolcreaterole
              AND NOT rolreplication
              AND NOT rolbypassrls
        ) THEN
            RAISE EXCEPTION 'Rol funcional % dejo de ser NOLOGIN/minimo privilegio.', functional_name;
        END IF;
    END LOOP;

    WITH expected(member_name, role_name) AS (
        VALUES
            ('jp_login_migrator', 'jp_migrator'),
            ('jp_login_api', 'jp_app'),
            ('jp_login_backoffice', 'jp_backoffice'),
            ('jp_login_worker', 'jp_worker'),
            ('jp_login_readonly', 'jp_readonly')
    )
    SELECT count(*)
    INTO expected_memberships
    FROM expected e
    JOIN pg_catalog.pg_roles member_role
      ON member_role.rolname = e.member_name
    JOIN pg_catalog.pg_roles granted_role
      ON granted_role.rolname = e.role_name
    JOIN pg_catalog.pg_auth_members membership
      ON membership.member = member_role.oid
     AND membership.roleid = granted_role.oid
    WHERE NOT membership.admin_option;

    IF expected_memberships <> 5 THEN
        RAISE EXCEPTION 'Se esperaban 5 memberships funcionales directos y existen %.', expected_memberships;
    END IF;

    SELECT count(*)
    INTO actual_count
    FROM pg_catalog.pg_auth_members membership
    JOIN pg_catalog.pg_roles member_role
      ON member_role.oid = membership.member
    JOIN pg_catalog.pg_roles granted_role
      ON granted_role.oid = membership.roleid
    WHERE member_role.rolname IN (
        'jp_login_migrator',
        'jp_login_api',
        'jp_login_backoffice',
        'jp_login_worker',
        'jp_login_readonly'
    )
      AND granted_role.rolname IN (
        'jp_owner',
        'jp_migrator',
        'jp_app',
        'jp_backoffice',
        'jp_worker',
        'jp_readonly'
    );

    IF actual_count <> 5 THEN
        RAISE EXCEPTION 'Existen memberships funcionales directos inesperados: %.', actual_count;
    END IF;

    IF pg_has_role('jp_login_api', 'jp_owner', 'MEMBER')
       OR pg_has_role('jp_login_api', 'jp_migrator', 'MEMBER') THEN
        RAISE EXCEPTION 'La API puede alcanzar owner/migrator.';
    END IF;

    IF pg_has_role('jp_login_worker', 'jp_owner', 'MEMBER')
       OR pg_has_role('jp_login_worker', 'jp_migrator', 'MEMBER') THEN
        RAISE EXCEPTION 'El worker puede alcanzar owner/migrator.';
    END IF;

    IF NOT pg_has_role('jp_login_migrator', 'jp_migrator', 'MEMBER')
       OR NOT pg_has_role('jp_login_migrator', 'jp_owner', 'MEMBER') THEN
        RAISE EXCEPTION 'La identidad de migracion no alcanza la cadena jp_migrator -> jp_owner.';
    END IF;

    IF NOT has_database_privilege('jp_login_api', current_database(), 'CONNECT')
       OR has_database_privilege('jp_login_api', current_database(), 'CREATE')
       OR has_database_privilege('jp_login_api', current_database(), 'TEMPORARY') THEN
        RAISE EXCEPTION 'Privilegios de base incorrectos para jp_login_api.';
    END IF;

    IF NOT has_database_privilege('jp_login_worker', current_database(), 'CONNECT')
       OR has_database_privilege('jp_login_worker', current_database(), 'CREATE')
       OR has_database_privilege('jp_login_worker', current_database(), 'TEMPORARY') THEN
        RAISE EXCEPTION 'Privilegios de base incorrectos para jp_login_worker.';
    END IF;

    IF NOT has_database_privilege('jp_login_readonly', current_database(), 'CONNECT')
       OR has_database_privilege('jp_login_readonly', current_database(), 'CREATE')
       OR has_database_privilege('jp_login_readonly', current_database(), 'TEMPORARY') THEN
        RAISE EXCEPTION 'Privilegios de base incorrectos para jp_login_readonly.';
    END IF;

    IF NOT has_schema_privilege('jp_login_migrator', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'jp_login_migrator no puede gestionar __EFMigrationsHistory.';
    END IF;

    IF has_schema_privilege('jp_login_api', 'catalog', 'CREATE')
       OR has_schema_privilege('jp_login_worker', 'ops', 'CREATE')
       OR has_schema_privilege('jp_login_readonly', 'catalog', 'CREATE') THEN
        RAISE EXCEPTION 'Un LOGIN runtime posee CREATE sobre un esquema de aplicacion.';
    END IF;

    IF NOT has_table_privilege('jp_login_api', 'catalog.artist', 'SELECT')
       OR has_table_privilege('jp_login_api', 'catalog.artist', 'INSERT')
       OR has_table_privilege('jp_login_api', 'catalog.artist', 'DELETE') THEN
        RAISE EXCEPTION 'Matriz jp_app inesperada sobre catalog.artist.';
    END IF;

    IF NOT has_table_privilege('jp_login_backoffice', 'catalog.artist', 'SELECT')
       OR NOT has_table_privilege('jp_login_backoffice', 'catalog.artist', 'INSERT')
       OR NOT has_table_privilege('jp_login_backoffice', 'catalog.artist', 'UPDATE')
       OR has_table_privilege('jp_login_backoffice', 'catalog.artist', 'DELETE') THEN
        RAISE EXCEPTION 'Matriz jp_backoffice inesperada sobre catalog.artist.';
    END IF;

    IF NOT has_table_privilege('jp_login_worker', 'ops.idempotency_record', 'DELETE') THEN
        RAISE EXCEPTION 'jp_login_worker no hereda DML de jp_worker sobre ops.';
    END IF;

    IF NOT has_table_privilege('jp_login_readonly', 'catalog.v_public_song', 'SELECT')
       OR has_table_privilege('jp_login_readonly', 'catalog.artist', 'SELECT') THEN
        RAISE EXCEPTION 'jp_login_readonly excede o no alcanza su lectura publica minima.';
    END IF;

    SELECT count(*)
    INTO actual_count
    FROM pg_catalog.pg_class object
    JOIN pg_catalog.pg_namespace namespace
      ON namespace.oid = object.relnamespace
    JOIN pg_catalog.pg_roles owner_role
      ON owner_role.oid = object.relowner
    WHERE namespace.nspname IN (
        'identity','security','catalog','content','learning',
        'progress','editorial','configuration','ops'
    )
      AND object.relkind IN ('r', 'p')
      AND owner_role.rolname = 'jp_owner';

    IF actual_count <> 109 THEN
        RAISE EXCEPTION 'Se esperaban 109 tablas propiedad de jp_owner y existen %.', actual_count;
    END IF;

    SELECT count(*)
    INTO actual_count
    FROM pg_catalog.pg_namespace namespace
    JOIN pg_catalog.pg_roles owner_role
      ON owner_role.oid = namespace.nspowner
    WHERE namespace.nspname IN (
        'identity','security','catalog','content','learning',
        'progress','editorial','configuration','ops'
    )
      AND owner_role.rolname = 'jp_owner';

    IF actual_count <> 9 THEN
        RAISE EXCEPTION 'Se esperaban 9 schemas propiedad de jp_owner y existen %.', actual_count;
    END IF;

    SELECT count(*)
    INTO actual_count
    FROM pg_catalog.pg_policy policy
    JOIN pg_catalog.pg_class object
      ON object.oid = policy.polrelid
    JOIN pg_catalog.pg_namespace namespace
      ON namespace.oid = object.relnamespace
    WHERE namespace.nspname IN (
        'identity','security','catalog','content','learning',
        'progress','editorial','configuration','ops'
    );

    IF actual_count <> 99 THEN
        RAISE EXCEPTION 'Se esperaban 99 politicas RLS y existen %.', actual_count;
    END IF;

    -- Los LOGIN no reciben ACL de tablas directamente: todo acceso llega por
    -- exactamente un rol NOLOGIN funcional.
    SELECT count(*)
    INTO actual_count
    FROM pg_catalog.pg_class object
    CROSS JOIN LATERAL pg_catalog.aclexplode(
        coalesce(object.relacl, pg_catalog.acldefault('r', object.relowner))
    ) acl
    JOIN pg_catalog.pg_roles grantee
      ON grantee.oid = acl.grantee
    WHERE grantee.rolname IN (
        'jp_login_migrator',
        'jp_login_api',
        'jp_login_backoffice',
        'jp_login_worker',
        'jp_login_readonly'
    );

    IF actual_count <> 0 THEN
        RAISE EXCEPTION 'Existen grants directos de tabla sobre identidades LOGIN: %.', actual_count;
    END IF;

    IF to_regclass('public."__EFMigrationsHistory"') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM pg_catalog.pg_class object
           JOIN pg_catalog.pg_namespace namespace
             ON namespace.oid = object.relnamespace
           JOIN pg_catalog.pg_roles owner_role
             ON owner_role.oid = object.relowner
           WHERE namespace.nspname = 'public'
             AND object.relname = '__EFMigrationsHistory'
             AND owner_role.rolname = 'jp_migrator'
       ) THEN
        RAISE EXCEPTION '__EFMigrationsHistory no pertenece a jp_migrator.';
    END IF;
END;
$verify$;

SELECT
    5 AS separated_login_identities,
    6 AS functional_nologin_roles,
    109 AS tables_owned_by_jp_owner,
    9 AS schemas_owned_by_jp_owner,
    99 AS rls_policies,
    'OK: identidades PostgreSQL separadas y minimo privilegio verificados.' AS result;
