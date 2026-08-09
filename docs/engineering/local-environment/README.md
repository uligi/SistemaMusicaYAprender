# Entorno local reproducible — BL-MVP-006

El backlog exige que un único comando levante web/API, worker, PostgreSQL, almacén de objetos
de desarrollo, SMTP sink y collector.

La arquitectura de referencia también define Docker Compose para local con app, worker,
PostgreSQL, objeto de desarrollo, SMTP sink y collector.

## Servicios

| Servicio       | Contenedor              |        Puerto local | Propósito                                             |
| -------------- | ----------------------- | ------------------: | ----------------------------------------------------- |
| web            | React compilado + Nginx |                5173 | Cliente web; `/api/` se enruta internamente a la API  |
| api            | ASP.NET Core 9          |                5080 | API del monolito modular                              |
| worker         | .NET 9                  |                   — | Trabajos en segundo plano                             |
| postgres       | PostgreSQL 18           |                5432 | Fuente de verdad relacional                           |
| object-store   | MinIO                   |         9000 / 9001 | Almacén S3-compatible solo para desarrollo            |
| smtp-sink      | Mailpit                 |         1025 / 8025 | Captura correos de desarrollo; no entrega correo real |
| otel-collector | OpenTelemetry Collector | 4317 / 4318 / 13133 | Recibe telemetría OTLP y expone health local          |

## Inicio

Desde la raíz del repositorio:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\local\start.ps1
```

Ese único comando:

1. verifica Docker y Docker Compose;
2. crea `.env` desde `.env.example` si todavía no existe;
3. construye las imágenes de web/API/worker;
4. levanta todos los servicios;
5. muestra su estado y las URLs locales.

## Verificación

```powershell
.\scripts\local\verify-running.ps1
```

Debe terminar con:

`OK: los 7 servicios estan ejecutandose y web/API/collector responden.`

## Detener sin borrar datos

```powershell
.\scripts\local\stop.ps1
```

## Reinicio destructivo de datos locales

```powershell
.\scripts\local\reset.ps1
```

`reset.ps1` elimina los volúmenes locales. No se usa contra datos reales.

## Seguridad

Los valores de `.env.example` son credenciales públicas e intencionalmente débiles de **desarrollo local**.
`.env` está excluido por Git. BL-MVP-009 implementará la configuración y secret store reales; este incremento
no convierte estas credenciales en secretos de producción.

## Decisiones de versiones

- PostgreSQL: `postgres:18`, coherente con la línea base.
- .NET build: SDK `9.0.314`; runtime ASP.NET Core `9.0.16`, coherentes con el target temporal .NET 9.
- Node: `24.18.0-alpine3.24`, igual que la toolchain local.
- Nginx: `1.30.4-alpine3.24`.
- Mailpit: `v1.30.0`.
- OpenTelemetry Collector contrib: `0.157.0`.
- MinIO: `RELEASE.2025-10-15T17-29-55Z`, únicamente como S3-compatible de desarrollo.

El proveedor de objeto sigue detrás del futuro `IObjectStore`; BL-MVP-016 define ese contrato.

## PostgreSQL 18 y persistencia

PostgreSQL 18 usa directorios de datos específicos por versión dentro de /var/lib/postgresql.
Por ello el volumen local se monta en /var/lib/postgresql, no en /var/lib/postgresql/data.
Este diseño también evita cruzar límites de montaje durante futuras operaciones de pg_upgrade.
