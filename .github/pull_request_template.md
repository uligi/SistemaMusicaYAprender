# Pull Request trazado al MVP

## Issue / backlog

- BL-MVP: <!-- Ej.: BL-MVP-005 -->
- Issue: <!-- Ej.: Closes #123 -->
- Fase: <!-- F0-F6 -->
- Épica: <!-- EP-00-EP-13 -->
- Tipo: <!-- Historia / Habilitador -->

## Objetivo

<!-- Resultado observable que entrega este PR. -->

## Trazabilidad

- CU/CA/UI/CE:
- RF/RN:
- RNF:
- ARC/DDC/DI:

> Para campos no aplicables, escriba `No aplica` y explique brevemente por qué.

## Cambios realizados

<!-- Resuma cambios de frontend, backend, datos, infraestructura y documentación. -->

## Datos y permisos

- Esquemas/entidades afectados:
- Autorización/permisos:
- Privacidad/retención:
- Concurrencia/idempotencia:
- Migración/compatibilidad:

## Riesgos

- Riesgo de datos: <!-- No aplica / Bajo / Medio / Alto -->
- Riesgo de seguridad/privacidad: <!-- No aplica / Bajo / Medio / Alto -->
- Riesgo de migración: <!-- No aplica / Bajo / Medio / Alto -->
- Mitigaciones:

## Pruebas ejecutadas

- [ ] Unitarias aplicables
- [ ] Integración aplicable
- [ ] Arquitectura / límites modulares
- [ ] E2E aplicable
- [ ] Accesibilidad aplicable
- [ ] Seguridad aplicable
- [ ] Rendimiento aplicable
- [ ] `scripts/check-quality.ps1` o equivalente aprobado

Detalle / comandos / resultados:

<!-- Incluya comandos, ejecuciones CI y resultados relevantes. -->

## Evidencia

- Commit/candidato:
- Ejecución CI:
- Capturas/reportes:
- Ambiente:
- Fecha:
- Responsable:

## Revisión requerida

- [ ] Cambio normal: requiere al menos una aprobación independiente antes de una rama protegida.
- [ ] Si modifica autenticación, permisos, criptografía o una migración destructiva: requiere dos aprobaciones.

## Definition of Done

- [ ] Código revisado y compilación limpia.
- [ ] Contratos/migraciones compatibles o plan de transición documentado.
- [ ] Pruebas positivas/negativas y controles de autorización, concurrencia e idempotencia según riesgo.
- [ ] Trazabilidad a RF/RN, CU/CA, RNF y ARC/DDC/DI aplicables.
- [ ] Cero vulnerabilidades críticas/altas abiertas en el alcance del cambio.
- [ ] Sin excepción no aprobada de accesibilidad, privacidad o integridad del flujo esencial.
- [ ] Observabilidad/runbook actualizados cuando cambia la operación.
- [ ] Evidencia reproducible asociada al mismo commit/candidato.
- [ ] Documentación técnica refleja el comportamiento real.
