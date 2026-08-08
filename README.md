# Música y Aprender

Plataforma de aprendizaje de japonés mediante canciones.

## Estado de construcción

- BL-MVP-001: estructura inicial del monorrepositorio.
- BL-MVP-002: toolchain y dependencias reproducibles sobre .NET 9 por compatibilidad temporal con Visual Studio.
- BL-MVP-003: análisis estático, formato reproducible y categorización de carpetas.

## Toolchain local

- .NET SDK: banda 9.0.3xx.
- Node.js: 24.18.0.
- npm: 11.16.0.
- React: 19.2.7.
- TypeScript: 7.0.2.

## Primer uso después de extraer este incremento

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
npm.cmd install --package-lock-only
.\scripts\format-code.ps1
.\scripts\check-quality.ps1
```

El primer `npm.cmd install --package-lock-only` actualiza el lockfile con las herramientas de formato incorporadas por BL-MVP-003.

## Organización

La estructura evita carpetas genéricas masivas. Frontend, API, módulos, pruebas y PostgreSQL se subdividen por responsabilidad. Ver `docs/conventions/folder-categorization.md`.
