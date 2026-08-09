# Configuración externa y secret store — BL-MVP-009 / BL-MVP-012

La imagen es idéntica entre ambientes. La configuración no secreta y los secretos tienen ciclos separados.

## Contrato

La aplicación recibe configuración no secreta mediante proveedores normales de .NET y secretos mediante
archivos montados, por defecto en `/run/secrets`.

`config/secrets/manifest.json` versiona únicamente nombres, propósito y consumidores; jamás valores.

BL-MVP-012 separa las credenciales PostgreSQL:

| Identidad             | Rol heredado    | Secreto                        | Consumidor                        |
| --------------------- | --------------- | ------------------------------ | --------------------------------- |
| `jp_login_migrator`   | `jp_migrator`   | `postgres_migrator_password`   | migrador explícito                |
| `jp_login_api`        | `jp_app`        | `postgres_api_password`        | API                               |
| `jp_login_backoffice` | `jp_backoffice` | `postgres_backoffice_password` | pool privilegiado futuro/separado |
| `jp_login_worker`     | `jp_worker`     | `postgres_worker_password`     | Worker                            |
| `jp_login_readonly`   | `jp_readonly`   | `postgres_readonly_password`   | herramientas de lectura           |

`musica_local` y `postgres_password` quedan reservados para DBA/bootstrap local. No se montan en API ni Worker.

## Runtime

`Database:PasswordSecret` selecciona el nombre del archivo secreto correspondiente al proceso.
`ExternalConfigurationExtensions` valida ese nombre y construye la cadena de conexión solo en memoria.

## Rotación

`scripts/local/verify-secret-rotation.ps1` rota las credenciales DBA, migrador, API, backoffice,
Worker, readonly y object store; después revalida health, autenticación, permisos y ausencia de valores
en `docker inspect`.

## Seguridad

- `jp_owner`, `jp_migrator`, `jp_app`, `jp_backoffice`, `jp_worker` y `jp_readonly` continúan NOLOGIN.
- cada LOGIN tiene un único membership funcional directo;
- API/Worker no pueden asumir owner/migrator;
- ninguna identidad runtime es SUPERUSER, CREATEDB, CREATEROLE, REPLICATION o BYPASSRLS;
- los valores secretos no viven en Git, `.env`, M19 ni artefactos CI.
