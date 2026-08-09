-- BL-MVP-012
-- Identidades LOGIN externas separadas de los roles NOLOGIN de permisos.
-- NO contiene contrasenas. Los valores se sincronizan desde el secret store.
BEGIN;

DO $roles$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'jp_login_migrator') THEN
        CREATE ROLE jp_login_migrator LOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'jp_login_api') THEN
        CREATE ROLE jp_login_api LOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'jp_login_backoffice') THEN
        CREATE ROLE jp_login_backoffice LOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'jp_login_worker') THEN
        CREATE ROLE jp_login_worker LOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'jp_login_readonly') THEN
        CREATE ROLE jp_login_readonly LOGIN;
    END IF;
END;
$roles$;

ALTER ROLE jp_login_migrator
WITH
    LOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

ALTER ROLE jp_login_api
WITH
    LOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

ALTER ROLE jp_login_backoffice
WITH
    LOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

ALTER ROLE jp_login_worker
WITH
    LOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

ALTER ROLE jp_login_readonly
WITH
    LOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

-- Normaliza memberships directos antes de conceder el unico rol funcional permitido.
REVOKE jp_owner,
jp_migrator,
jp_app,
jp_backoffice,
jp_worker,
jp_readonly
FROM
    jp_login_migrator;

REVOKE jp_owner,
jp_migrator,
jp_app,
jp_backoffice,
jp_worker,
jp_readonly
FROM
    jp_login_api;

REVOKE jp_owner,
jp_migrator,
jp_app,
jp_backoffice,
jp_worker,
jp_readonly
FROM
    jp_login_backoffice;

REVOKE jp_owner,
jp_migrator,
jp_app,
jp_backoffice,
jp_worker,
jp_readonly
FROM
    jp_login_worker;

REVOKE jp_owner,
jp_migrator,
jp_app,
jp_backoffice,
jp_worker,
jp_readonly
FROM
    jp_login_readonly;

GRANT jp_migrator TO jp_login_migrator;

GRANT jp_app TO jp_login_api;

GRANT jp_backoffice TO jp_login_backoffice;

GRANT jp_worker TO jp_login_worker;

GRANT jp_readonly TO jp_login_readonly;

-- El migrador necesita que cualquier objeto EF no cualificado (en particular
-- __EFMigrationsHistory) resuelva a public. PUBLIC no tiene CREATE sobre public
-- y solo jp_migrator lo recibe en 02_database_access.sql.
ALTER ROLE jp_login_migrator
SET
    search_path = public,
    pg_catalog;

-- Los procesos runtime mantienen pg_catalog primero y no crean objetos.
ALTER ROLE jp_login_api
SET
    search_path = pg_catalog,
    public;

ALTER ROLE jp_login_backoffice
SET
    search_path = pg_catalog,
    public;

ALTER ROLE jp_login_worker
SET
    search_path = pg_catalog,
    public;

ALTER ROLE jp_login_readonly
SET
    search_path = pg_catalog,
    public;

COMMIT;
