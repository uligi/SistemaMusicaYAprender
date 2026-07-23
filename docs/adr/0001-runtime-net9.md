# ADR-0001 — Runtime del incremento inicial

## Estado

Aceptado para el entorno de desarrollo actual.

## Decisión

Los proyectos del incremento BL-MVP-001 usarán `net9.0` como framework de destino.

## Motivo

La versión de Visual Studio utilizada por el proyecto no admite proyectos con destino `net10.0`. Mantener `net9.0` permite abrir, restaurar, compilar y depurar la solución con el entorno disponible sin modificar la estructura del monolito modular.

## Consecuencias

- Todos los proyectos heredan `net9.0` desde `Directory.Build.props`.
- No se cambia la separación de módulos, contratos ni dependencias.
- Una migración futura a .NET 10 requerirá actualizar el SDK y una versión compatible de Visual Studio, además de ejecutar las pruebas completas.
