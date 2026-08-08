# BL-MVP-004 — Pipeline CI inicial

## Objetivo

GitHub Actions ejecuta en cada `push` a `main`, Pull Request y ejecución manual:

1. restauración exacta de .NET y npm desde lockfiles;
2. TypeScript estricto;
3. verificación de formato;
4. compilación de React/Vite;
5. `dotnet format` y analizadores;
6. compilación completa de la solución;
7. pruebas unitarias xUnit;
8. pruebas de arquitectura y límites entre módulos;
9. prueba transaccional contra PostgreSQL 18 recién creado;
10. publicación de evidencias como artefacto de GitHub Actions.

El pipeline tiene `timeout-minutes: 15` para mantener visible desde el inicio el objetivo de
retroalimentación definido por RNF-MVP-139.

## Migración sobre base vacía

BL-MVP-004 crea la infraestructura de CI y comprueba que PostgreSQL 18 puede ejecutar una
migración transaccional sobre una base vacía sin dejar estado parcial.

Todavía **no ejecuta el SQL físico completo como migración EF**. Esa integración pertenece a
BL-MVP-010 y BL-MVP-011. Cuando esos elementos se implementen, el paso
`scripts/ci/database/verify-empty-migration.sh` se reemplazará/extenderá para aplicar el
bootstrap y la migración inicial real y verificar las 109 tablas y semillas.

Si `sistema de musica/MVP_PostgreSQL_18_Master.sql` ya existe en el repositorio, el pipeline
registra su SHA-256 en la evidencia para conservar trazabilidad, pero no lo instala todavía.

## Evidencias

Cada ejecución publica un artefacto llamado:

`ci-evidence-<run>-<attempt>`

que contiene, según hasta dónde haya llegado la ejecución:

- manifiesto con commit y versiones de herramientas;
- resultados TRX de pruebas unitarias;
- resumen de la prueba PostgreSQL;
- hash del SQL maestro si está disponible;
- compilado `dist/` del frontend.

## Carpetas

```text
.github/
└── workflows/
    └── ci.yml

scripts/
└── ci/
    ├── database/
    │   └── verify-empty-migration.sh
    └── evidence/
        └── write-manifest.sh

tests/
└── UnitTests/
    └── BuildingBlocks/
        └── Domain/
            └── Entities/
                └── EntityTests.cs
```

## Instalación local del incremento

Después de copiar el paquete sobre la raíz del repositorio:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-004.ps1
```

El script actualiza `packages.lock.json` debido a las nuevas dependencias de xUnit y ejecuta la
puerta local.

Después:

```powershell
git status
git add .
git commit -m "ci: implementar pipeline inicial [BL-MVP-004]"
git push origin main
```

La primera ejecución real podrá verse en la pestaña **Actions** de GitHub.
