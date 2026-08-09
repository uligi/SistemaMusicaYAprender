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
