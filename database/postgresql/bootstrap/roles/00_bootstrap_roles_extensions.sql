-- BL-MVP-010
-- PostgreSQL 18 - bootstrap de roles y extensiones.
-- Ejecutar con una identidad DBA. No contiene contrasenas ni secretos.
--
-- Fuente normativa: Diseno fisico PostgreSQL MVP.
-- Este archivo debe poder ejecutarse mas de una vez sin cambiar el resultado final.
BEGIN;

REVOKE CREATE ON SCHEMA public
FROM
    PUBLIC;

CREATE EXTENSION IF NOT EXISTS pg_trgm
WITH
    SCHEMA public;

CREATE EXTENSION IF NOT EXISTS btree_gist
WITH
    SCHEMA public;

DO $roles$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'jp_owner'
    ) THEN
        CREATE ROLE jp_owner
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'jp_migrator'
    ) THEN
        CREATE ROLE jp_migrator
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'jp_app'
    ) THEN
        CREATE ROLE jp_app
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'jp_backoffice'
    ) THEN
        CREATE ROLE jp_backoffice
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'jp_worker'
    ) THEN
        CREATE ROLE jp_worker
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'jp_readonly'
    ) THEN
        CREATE ROLE jp_readonly
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS;
    END IF;
END;
$roles$;

GRANT jp_owner TO jp_migrator;

ALTER ROLE jp_app
SET
    search_path = pg_catalog,
    public;

ALTER ROLE jp_backoffice
SET
    search_path = pg_catalog,
    public;

ALTER ROLE jp_worker
SET
    search_path = pg_catalog,
    public;

ALTER ROLE jp_readonly
SET
    search_path = pg_catalog,
    public;

COMMIT;

-- Las identidades LOGIN reales se crean fuera de este archivo y reciben
-- membresia de uno de estos roles NOLOGIN. BL-MVP-012 separa esas identidades.
