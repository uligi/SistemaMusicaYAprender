# Reglas de dependencias

## Flujo permitido

```text
Domain <- Application <- Infrastructure
   ^            ^              ^
   +--------- Contracts -------+

Modules -> BuildingBlocks
API/Worker -> Modules + BuildingBlocks
Tests -> proyectos bajo prueba
```

## Prohibiciones

- Dominio hacia EF Core, HTTP, archivos, YouTube, telemetría o UI.
- Referencias directas de un módulo a otro.
- Acceso directo a tablas de otro esquema como mecanismo de integración.
- Eventos sin nombre y versión estables.
- Colocar credenciales, secretos o datos personales en contratos compartidos.

La comprobación inicial se ejecuta con `scripts/check-module-boundaries.sh` o `scripts/check-module-boundaries.ps1`.
