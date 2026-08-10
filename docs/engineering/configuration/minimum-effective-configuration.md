# Publicación mínima de configuración efectiva

## Propósito

BL-MVP-035 hace observable la línea base de M19 que ya existe en la migración inicial. No introduce una segunda fuente de datos: el SQL maestro y `02_seed_mvp.sql` siguen siendo la fuente física, mientras los manifiestos de aplicación declaran únicamente qué publicaciones y sustitutos seguros necesita el corte F1.

## Catálogos y sustitutos seguros

| Catálogo             | Sustituto seguro |
| -------------------- | ---------------- |
| `ACCOUNT_STATUS`     | `DISABLED`       |
| `REVISION_STATUS`    | `DRAFT`          |
| `PUBLICATION_STATUS` | `WITHDRAWN`      |
| `PACKAGE_STATUS`     | `DRAFT`          |
| `SESSION_STATUS`     | `PAUSED`         |
| `INSTANCE_STATUS`    | `CREATED`        |
| `JOB_STATUS`         | `NEEDS_REVIEW`   |
| `PRIVACY_STATUS`     | `RECEIVED`       |
| `LANGUAGE`           | `ES`             |
| `PROVIDER`           | `YOUTUBE`        |
| `JLPT_LEVEL`         | `N5`             |
| `DATA_CLASS`         | `RESTRICTED`     |

Cada definición y entrada debe estar activa, versionada y vigente. Las 59 entradas mínimas deben incluir etiqueta `es`. El sustituto no concede permisos ni convierte por sí solo una entidad a ese estado; es el valor conservador que un consumidor puede usar cuando su contrato requiera degradación explícita.

## Parámetros y valores predeterminados seguros

| Clave                          | Tipo     | Predeterminado seguro |
| ------------------------------ | -------- | --------------------: |
| `PLAYER_SYNC_TOLERANCE_MS`     | entero   |                   120 |
| `SESSION_IDLE_MINUTES`         | entero   |                    30 |
| `SESSION_ABSOLUTE_HOURS`       | entero   |                    24 |
| `EDITORIAL_LOCK_SECONDS`       | entero   |                   300 |
| `IDEMPOTENCY_RETENTION_HOURS`  | entero   |                    24 |
| `MAX_JOB_ATTEMPTS`             | entero   |                     8 |
| `SEARCH_MIN_QUERY_LENGTH`      | entero   |                     2 |
| `MFA_REQUIRED_PRIVILEGED`      | booleano |                `true` |
| `PUBLICATION_DEFAULT_LANGUAGE` | texto    |                  `es` |
| `JOB_ATTEMPT_RETENTION_DAYS`   | entero   |                    90 |

El valor efectivo debe resolverse en ámbito `GLOBAL`, conservar `parameter_version_id`, `version_no`, vigencia, checksum y `projection_version`, y mantener el mismo tipo JSON declarado. `default_value` es el sustituto seguro; no obliga a que una futura versión efectiva tenga siempre ese mismo valor.

## Roles y políticas

Los roles mínimos son `STUDENT`, `EDITOR`, `REVIEWER` y `ADMIN`. Todos deben estar activos y versionados. `STUDENT` es el sustituto seguro y no debe interpretarse como elevación automática: el motor de autorización de BL-MVP-030 seguirá denegando por defecto.

| Clase / finalidad             | Días | Disparador    |
| ----------------------------- | ---: | ------------- |
| `INTERNAL / JOB_ATTEMPT`      |   90 | `FINISHED_AT` |
| `RESTRICTED / SECURITY_EVENT` |  365 | `OCCURRED_AT` |
| `RESTRICTED / SECURITY_TOKEN` |    7 | `EXPIRES_AT`  |

## Salud y degradación

El check `minimum-configuration` participa en `/health/ready` y `/health/dependencies`:

- `Healthy`: la base está accesible y todo el contrato mínimo está publicado;
- `Unhealthy`: la base responde, pero falta un elemento, versión, vigencia o sustituto seguro;
- `Degraded`: la inspección no puede acceder a PostgreSQL o excede el tiempo límite.

El endpoint no devuelve valores efectivos, conteos internos ni nombres ausentes; solo estado, duración y descripción. Ante degradación, cada consumidor conserva la última versión válida aplicada; si no existe, usa el sustituto seguro declarado y conserva evidencia de la versión aplicada según RF-M19-064 y RF-M19-229.

## Seguridad y evolución

M19 no acepta contraseñas, secretos, credenciales, llaves privadas ni access keys como parámetros comunes. Los secretos siguen el secret store externo de BL-MVP-009. BL-MVP-036 podrá crear nuevas versiones con simulación, motivo, autorización y auditoría, pero no debe borrar ni reescribir valores históricos ni eliminar el sustituto seguro.
