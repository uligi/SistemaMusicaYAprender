# BL-MVP-036 — Administrar catálogos y parámetros versionados

## Definición normativa

- Fase: F1 — Identidad, acceso y configuración.
- Épica: EP-04 — Preferencias y configuración.
- Tipo: Historia.
- Traza: `CU-MVP-24`; `UI-MVP-030`; `CE-09`, `CE-14`.
- Story Points: 8.
- Dependencias: BL-MVP-030, BL-MVP-033 y BL-MVP-035.
- Resultado: **cambiar un valor exige permiso, impacto, vigencia y motivo; valores usados históricamente no se borran físicamente.**

## Corte funcional

BL-MVP-036 habilita `UI-MVP-030` en `/administracion/configuracion` y expone una administración protegida de los catálogos y parámetros P0 ya publicados por BL-MVP-035.

La lectura y simulación requieren `CONFIG.MANAGE`; la activación exige además `CONFIG.APPROVE`. Todas las operaciones requieren verificación privilegiada reciente y las mutaciones POST validan antiforgery. La visibilidad de la ruta nunca sustituye la autorización del servidor.

Cada cambio exige:

- objeto efectivo existente y módulo propietario;
- valor compatible con el tipo o esquema publicado;
- ámbito explícito;
- vigencia final válida cuando se informa;
- motivo (hasta 160 caracteres);
- impacto y dependencias (hasta 240 caracteres);
- versión esperada para detectar concurrencia;
- ausencia de claves o campos con semántica inequívoca de secreto.

La activación se ejecuta dentro de una única transacción backoffice. M19 registra `configuration_change_set`, `configuration_change_item` y `configuration_activation`; un adaptador de M18 escribe `security.audit_event` en esa misma transacción con correlación, digest antes/después, motivo e impacto.

## Historial

BL-MVP-036 no ejecuta `DELETE` sobre `configuration.parameter_version` ni `configuration.catalog_entry`.

Al sustituir un valor, solo se cierra la vigencia de la fila anterior y se crea una nueva fila. En parámetros, `effective_parameter` pasa a la nueva versión. En catálogos, el código estable se conserva con una nueva identidad física. El valor histórico continúa reconstruible.

Un reintento que encuentra exactamente el mismo valor y vigencia ya efectivos responde como `alreadyApplied` y no crea otra versión lógica.

## Límites

- No cambia el SQL maestro ni la migración física; usa las tablas, exclusiones de vigencia y grants backoffice ya existentes.
- No crea definiciones de parámetros, catálogos ni entradas nuevas; administra únicamente valores P0 efectivos existentes.
- No introduce un almacén de secretos dentro de M19.
- No convierte permisos en roles ni hardcodea `ADMIN`.
- No implementa importación/exportación masiva ni programación futura de activaciones.
- La edición modifica únicamente metadatos de ciclo de vida de la versión previa (`valid_to` y `status_code`); su valor histórico no se reescribe.

## Evidencia

- `tests/E2ETests/configuration-administration.spec.ts`: UI-MVP-030 y axe/WCAG.
- `scripts/ci/configuration/verify-versioned-configuration-administration.sh`: sesión real, autorización, step-up, CSRF, simulación, activación, concurrencia/reintento, rechazo de secretos, auditoría e historial físico.
- El smoke restaura al final los valores efectivos de referencia, dejando las revisiones históricas como evidencia.
- CI publica `artifacts/postgres/versioned-configuration-administration-summary.txt`.
