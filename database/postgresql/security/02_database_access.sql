-- BL-MVP-012
-- Ejecutar conectado a la base objetivo con -v database_name=<identificador>.
-- No contiene secretos.

REVOKE CONNECT, TEMPORARY ON DATABASE :"database_name" FROM PUBLIC;

GRANT CONNECT ON DATABASE :"database_name"
    TO jp_migrator, jp_app, jp_backoffice, jp_worker, jp_readonly;

REVOKE CREATE, TEMPORARY ON DATABASE :"database_name"
    FROM jp_migrator, jp_app, jp_backoffice, jp_worker, jp_readonly;

-- El DDL embebido hace SET LOCAL ROLE jp_owner para crear los nueve esquemas.
GRANT CREATE ON DATABASE :"database_name" TO jp_owner;

-- BL-MVP-025. La búsqueda de reenvío es la única excepción pública al RLS
-- por propietario: devuelve solo el UUID opaco de una cuenta PENDING cuyo
-- hash de correo coincide. La función queda con search_path fijo y sin
-- privilegio PUBLIC; la API nunca devuelve este resultado al cliente.
DO $account_verification_lookup$
BEGIN
    IF to_regclass('security.account') IS NOT NULL THEN
        EXECUTE $function$
            CREATE OR REPLACE FUNCTION security.resolve_pending_account_for_verification(
                p_email_lookup_hash bytea
            )
            RETURNS uuid
            LANGUAGE sql
            STABLE
            SECURITY DEFINER
            SET search_path = pg_catalog
            AS $body$
                SELECT account.account_id
                FROM security.account AS account
                WHERE octet_length(p_email_lookup_hash) = 32
                  AND account.email_lookup_hash = p_email_lookup_hash
                  AND account.status_code = 'PENDING'
                  AND account.verified_at IS NULL
                LIMIT 1
            $body$
        $function$;

        REVOKE ALL ON FUNCTION security.resolve_pending_account_for_verification(bytea)
            FROM PUBLIC;
        GRANT EXECUTE ON FUNCTION security.resolve_pending_account_for_verification(bytea)
            TO jp_app;
    END IF;
END;
$account_verification_lookup$;

-- BL-MVP-026. El runtime solo puede resolver una credencial activa mediante
-- el hash HMAC del correo y una sesion mediante el hash SHA-256 del token
-- opaco. Las funciones fijan search_path, no aceptan valores de longitud
-- inesperada y no quedan disponibles para PUBLIC. Ningun dato se devuelve al
-- cliente; la API usa el resultado exclusivamente para autenticar y validar la
-- revocacion en el servidor.
DO $personal_session_access$
BEGIN
    IF to_regclass('security.account') IS NOT NULL
       AND to_regclass('security.credential') IS NOT NULL
       AND to_regclass('security.session') IS NOT NULL THEN
        EXECUTE $function$
            CREATE OR REPLACE FUNCTION security.resolve_active_password_credential(
                p_email_lookup_hash bytea
            )
            RETURNS TABLE (
                account_id uuid,
                credential_hash text,
                credential_algorithm varchar(64),
                credential_parameters text
            )
            LANGUAGE sql
            STABLE
            SECURITY DEFINER
            SET search_path = pg_catalog
            AS $body$
                SELECT
                    account.account_id,
                    credential.hash,
                    credential.algorithm,
                    credential.parameters
                FROM security.account AS account
                INNER JOIN security.credential AS credential
                    ON credential.account_id = account.account_id
                   AND credential.active
                WHERE octet_length(p_email_lookup_hash) = 32
                  AND account.email_lookup_hash = p_email_lookup_hash
                  AND account.status_code = 'ACTIVE'
                  AND account.verified_at IS NOT NULL
                LIMIT 1
            $body$
        $function$;

        EXECUTE $function$
            CREATE OR REPLACE FUNCTION security.resolve_active_session(
                p_session_hash bytea
            )
            RETURNS TABLE (
                session_id uuid,
                account_id uuid,
                assurance_level varchar(64),
                created_at timestamptz,
                idle_expires_at timestamptz,
                absolute_expires_at timestamptz
            )
            LANGUAGE sql
            STABLE
            SECURITY DEFINER
            SET search_path = pg_catalog
            AS $body$
                SELECT
                    session.session_id,
                    session.account_id,
                    session.assurance_level,
                    session.created_at,
                    session.idle_expires_at,
                    session.absolute_expires_at
                FROM security.session AS session
                INNER JOIN security.account AS account
                    ON account.account_id = session.account_id
                WHERE octet_length(p_session_hash) = 32
                  AND session.session_hash = p_session_hash
                  AND session.assurance_level = 'PASSWORD'
                  AND session.revoked_at IS NULL
                  AND session.idle_expires_at > CURRENT_TIMESTAMP
                  AND session.absolute_expires_at > CURRENT_TIMESTAMP
                  AND account.status_code = 'ACTIVE'
                  AND account.verified_at IS NOT NULL
                LIMIT 1
            $body$
        $function$;

        EXECUTE $function$
            CREATE OR REPLACE FUNCTION security.revoke_active_session(
                p_session_hash bytea
            )
            RETURNS boolean
            LANGUAGE sql
            VOLATILE
            SECURITY DEFINER
            SET search_path = pg_catalog
            AS $body$
                WITH revoked AS (
                    UPDATE security.session AS session
                    SET revoked_at = CURRENT_TIMESTAMP
                    WHERE octet_length(p_session_hash) = 32
                      AND session.session_hash = p_session_hash
                      AND session.revoked_at IS NULL
                    RETURNING session.session_id
                )
                SELECT EXISTS (SELECT 1 FROM revoked)
            $body$
        $function$;

        REVOKE ALL ON FUNCTION security.resolve_active_password_credential(bytea)
            FROM PUBLIC;
        REVOKE ALL ON FUNCTION security.resolve_active_session(bytea)
            FROM PUBLIC;
        REVOKE ALL ON FUNCTION security.revoke_active_session(bytea)
            FROM PUBLIC;

        GRANT EXECUTE ON FUNCTION security.resolve_active_password_credential(bytea)
            TO jp_app;
        GRANT EXECUTE ON FUNCTION security.resolve_active_session(bytea)
            TO jp_app;
        GRANT EXECUTE ON FUNCTION security.revoke_active_session(bytea)
            TO jp_app;
    END IF;
END;
$personal_session_access$;

-- EF Core mantiene __EFMigrationsHistory en public. Solo el rol de migracion
-- puede crear/gestionar esa tabla; los roles runtime no reciben CREATE.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO jp_migrator;
REVOKE CREATE ON SCHEMA public
    FROM jp_app, jp_backoffice, jp_worker, jp_readonly;

DO $history$
BEGIN
    IF to_regclass('public."__EFMigrationsHistory"') IS NOT NULL THEN
        ALTER TABLE public."__EFMigrationsHistory" OWNER TO jp_migrator;
        REVOKE ALL ON TABLE public."__EFMigrationsHistory" FROM PUBLIC;
    END IF;
END;
$history$;
