# Música y Aprender

Plataforma web para aprender japonés mediante canciones.

Este incremento implementa **BL-MVP-001 — Crear la solución monorrepositorio y convenciones de carpetas** del backlog del MVP 1.0.

## Estado del incremento

La estructura separa explícitamente:

- aplicación web React;
- API ASP.NET Core;
- worker .NET;
- bloques compartidos;
- módulos P0 del monolito modular;
- pruebas;
- infraestructura;
- documentación y decisiones arquitectónicas.

No se crean proyectos ni tablas para M10-M14, M16 o M17 porque están diferidos fuera del MVP 1.0.

## Mapa de módulos P0

| Proyecto | Módulo propietario | Esquema PostgreSQL previsto |
|---|---|---|
| Identity | M01 — Usuarios y preferencias | `identity` |
| Catalog | M02 — Catálogo musical | `catalog` |
| Content | M03-M05 — Letra, traducción y análisis | `content` |
| Learning | M06-M08 — Aprendizaje, sesiones y ejercicios | `learning` |
| Progress | M09 — Progreso dentro de la canción | `progress` |
| Editorial | M15 — Gestión editorial | `editorial` |
| Security | M18 — Seguridad, roles y auditoría | `security` |
| Configuration | M19 — Administración y catálogos | `configuration` |

## Regla principal de dependencias

Los módulos no se referencian entre sí mediante `ProjectReference`. Cada módulo depende únicamente de los bloques compartidos. La API y el worker actúan como composición externa. La comunicación futura entre módulos se realizará mediante contratos de aplicación o eventos internos versionados.

## Comandos previstos

```bash
# Backend, cuando .NET 10 esté instalado
dotnet restore MusicaAprender.sln
dotnet build MusicaAprender.sln

# Cliente, después de fijar versiones y lockfile en BL-MVP-002
npm install
npm run dev --workspace @musica-aprender/web

# Comprobación de fronteras
bash scripts/check-module-boundaries.sh
```

## Próximo elemento

**BL-MVP-002 — Fijar SDK, runtime, gestores y lockfiles.**
