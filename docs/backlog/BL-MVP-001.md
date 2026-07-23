# BL-MVP-001 — Crear la solución monorrepositorio y convenciones de carpetas

## Tipo

Habilitador · F0 Cimientos · EP-00 Ingeniería y repositorio · 3 SP.

## Traza

MAN; ARC-01; todos los módulos P0.

## Resultado aceptable

La solución contiene frontend, backend, worker, pruebas, infraestructura y documentación sin dependencias circulares.

## Evidencia incluida

- `MusicaAprender.sln` con aplicaciones, BuildingBlocks, módulos y proyectos de prueba.
- `apps/web` con entrada React mínima.
- `apps/api` y `apps/worker` como raíces de composición.
- ocho módulos P0, sin proyectos para módulos diferidos.
- scripts y prueba de arquitectura para impedir referencias directas entre módulos.
- documentación de estructura, propiedad y reglas de dependencia.

## Pendiente de los elementos siguientes

Versiones exactas, lockfiles, análisis estático, CI, Docker Compose, health checks, telemetría, secretos y persistencia pertenecen a BL-MVP-002 a BL-MVP-022.
