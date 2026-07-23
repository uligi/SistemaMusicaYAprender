# ADR-0002 — Toolchain reproducible para el entorno compatible con Visual Studio 2022

- **Estado:** Aceptado con migración obligatoria.
- **Fecha:** 23 de julio de 2026.
- **Backlog:** BL-MVP-002.

## Contexto
La arquitectura de referencia utilizaba .NET 10, EF Core 10 y Npgsql 10. La versión de Visual Studio disponible no admite `net10.0`, mientras que la solución ya fue compilada y ejecutada correctamente con `net9.0`.

## Decisión

1. Mantener temporalmente `net9.0` con SDK de la banda 9.0.3xx y C# 13.
2. Alinear EF Core en 9.0.18 y el proveedor PostgreSQL en la rama 9.x.
3. Centralizar versiones NuGet y activar lockfiles por proyecto.
4. Usar Node.js 24.18.0 LTS, npm 11.16.0 y dependencias npm exactas.
5. Restaurar en CI únicamente en modo bloqueado.
6. Migrar a .NET 10 LTS antes del fin de soporte de .NET 9.

## Consecuencias

- La solución continúa funcionando en Visual Studio 2022 compatible con .NET 9.
- No se usan paquetes 10.x incompatibles con el destino actual.
- Las actualizaciones se realizan de forma explícita, revisada y acompañada por nuevos lockfiles.
- La adaptación es temporal: no debe llegar a producción después del fin de soporte de .NET 9.
