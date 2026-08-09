# Inventario de configuración por ambiente

La imagen de aplicación no cambia por ambiente. Las diferencias se inyectan externamente.

## No secretos

| Clave                         | Local             | CI/Pruebas           | Producción              |
| ----------------------------- | ----------------- | -------------------- | ----------------------- |
| `Database:Host`               | `postgres`        | inyectado            | inyectado               |
| `Database:Port`               | `5432`            | inyectado            | inyectado               |
| `Database:Name`               | `.env`            | efímero              | inyectado               |
| `Database:Username`           | `.env`            | efímero              | identidad de aplicación |
| `ObjectStore:Endpoint`        | interno Compose   | efímero              | endpoint privado        |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | collector Compose | collector CI/pruebas | collector operativo     |

## Secretos

Los nombres están inventariados en `config/secrets/manifest.json`; sus valores no aparecen aquí.
El contrato de runtime es un directorio de archivos montados, por defecto `/run/secrets`.

- Local: Docker Compose secrets respaldados por `secrets/local/`, que Git ignora.
- CI: archivos efímeros creados durante el job y nunca publicados como evidencia.
- Pruebas/producción: el secret store de la plataforma debe montar los mismos nombres.

M19 conserva únicamente parámetros funcionales no secretos. Referencias a secretos pueden existir
en seguridad/operación, pero nunca el valor secreto.
