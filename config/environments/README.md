# Inventario de configuración por ambiente

La imagen de aplicación no cambia por ambiente. Las diferencias se inyectan externamente.

## No secretos

| Clave                            | Local                      | CI/Pruebas           | Producción              |
| -------------------------------- | -------------------------- | -------------------- | ----------------------- |
| `Database:Host`                  | `postgres`                 | inyectado            | inyectado               |
| `Database:Port`                  | `5432`                     | inyectado            | inyectado               |
| `Database:Name`                  | `.env`                     | efímero              | inyectado               |
| `Database:Username` API          | `jp_login_api`             | `jp_login_api`       | identidad API           |
| `Database:Username` Worker       | `jp_login_worker`          | `jp_login_worker`    | identidad Worker        |
| `Database:PasswordSecret` API    | `postgres_api_password`    | mismo contrato       | referencia secret store |
| `Database:PasswordSecret` Worker | `postgres_worker_password` | mismo contrato       | referencia secret store |
| `ObjectStore:Endpoint`           | interno Compose            | efímero              | endpoint privado        |
| `OTEL_EXPORTER_OTLP_ENDPOINT`    | collector Compose          | collector CI/pruebas | collector operativo     |

`musica_local` permanece exclusivamente como identidad DBA local de infraestructura. La API y
el Worker no la usan como identidad runtime.

## Secretos

Los nombres están versionados en `config/secrets/manifest.json`; sus valores no aparecen allí.
El contrato de runtime es un directorio de archivos montados, por defecto `/run/secrets`.

- Local: Docker Compose secrets respaldados por `secrets/local/`, que Git ignora.
- CI: archivos efímeros creados durante el job y nunca publicados como evidencia.
- Pruebas/producción: el secret store de la plataforma monta los mismos nombres.
- Cada identidad PostgreSQL tiene un secreto diferente.

M19 conserva únicamente parámetros funcionales no secretos.
