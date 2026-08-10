# BL-MVP-035 — Publicar catálogos y parámetros efectivos mínimos

## Definición normativa

- Fase: F1 — Identidad, acceso y configuración.
- Épica: EP-04 — Preferencias y configuración.
- Tipo: Historia.
- Traza: `CU-MVP-24`; `UI-MVP-030`; M19; `CE-01`, `CE-09`, `CE-10`, `CE-14`.
- Story Points: 8.
- Dependencias: BL-MVP-011 y BL-MVP-014.
- Resultado: **idiomas, estados, roles, límites y políticas tienen código, versión, vigencia y sustituto seguro.**

## Corte funcional

La migración inicial ya publica la línea base física autorizada. Esta historia la convierte en un contrato operativo verificable sin duplicar ni reescribir las semillas:

- 12 catálogos y 59 entradas vigentes, localizadas en español;
- una entrada segura declarada por catálogo;
- 10 parámetros globales efectivos, tipados y versionados;
- un valor predeterminado seguro declarado por parámetro;
- 4 roles activos y versionados, con `STUDENT` como rol seguro;
- 3 políticas mínimas de retención, con duración, disparador y versión;
- ausencia de parámetros con nombres que aparenten secretos.

`MinimumPublishedConfigurationReader` y `MinimumRoleCatalogReader` inspeccionan el estado publicado con la identidad configurada para la API. El health check `minimum-configuration` se incorpora a readiness y dependencias: informa `Healthy` cuando el contrato está completo, `Unhealthy` si falta una publicación vigente y `Degraded` si el almacenamiento no está disponible. En degradación, los consumidores deben conservar la última versión válida o aplicar el sustituto seguro declarado.

## Límites de la historia

- No crea una interfaz de administración ni un endpoint mutable.
- No implementa simulación, aprobación, activación o reversión; corresponden a BL-MVP-036.
- No implementa el motor de permisos efectivos; corresponde a BL-MVP-030.
- No modifica el SQL maestro, la migración inicial ni sus hashes.
- No almacena secretos en M19.

## Evidencia automatizada

- `database/postgresql/tests/verify_minimum_effective_configuration.sql` comprueba publicación, tipo, versión, vigencia y sustitutos seguros.
- `scripts/ci/configuration/verify-minimum-effective-configuration.sh` ejecuta el contrato con `jp_login_api`, no con una identidad propietaria.
- `scripts/ci/identity/verify-personal-registration.sh` exige que la API real publique `minimum-configuration` en estado `Healthy`.
- CI conserva el resumen `artifacts/postgres/minimum-effective-configuration-summary.txt`.

## Instalación local en Windows

- Guía: `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-035.md`.
- Instalador y puerta local: `scripts/apply-bl-mvp-035.ps1`.

El instalador no ejecuta `git add`, commit ni push. BL-MVP-035 solo puede declararse GREEN después de completar sin omisiones la puerta local, los siete servicios, la prueba PostgreSQL/API y luego el CI del commit publicado.
