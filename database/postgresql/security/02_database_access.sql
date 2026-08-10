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
