# Música y Aprender — Base técnica del MVP

Monorrepositorio del MVP de aprendizaje de japonés mediante canciones.

## Estado del backlog

- BL-MVP-001: estructura inicial del monorrepositorio — completado.
- BL-MVP-002: SDK, runtime, gestores y lockfiles — preparado para validación local.

## Requisitos fijados

- Visual Studio 2022 compatible con .NET 9.
- SDK .NET 9, banda 9.0.3xx.
- Node.js 24.18.0 LTS.
- npm 11.16.0.
- PostgreSQL 18 se incorporará en los siguientes habilitadores de F0.

> .NET 9 finaliza soporte el 10 de noviembre de 2026. Debe planificarse la actualización a .NET 10 LTS antes de esa fecha.

## Primera restauración en Windows

Desde PowerShell en la raíz:

```powershell
npm install -g npm@11.16.0
.\scripts\restore-and-build.ps1
```

La primera ejecución genera `package-lock.json`. Después de comprobar que la compilación finaliza, ese archivo debe confirmarse en Git. Las ejecuciones posteriores usan `npm ci` y restauración NuGet bloqueada en CI.

## Comandos individuales

```powershell
# Validar versiones instaladas
.\scripts\check-toolchain.ps1

# Herramientas y backend
dotnet tool restore
dotnet restore MusicaAprender.sln
dotnet build MusicaAprender.sln --no-restore

# Frontend
npm install --package-lock-only
npm ci
npm run typecheck
npm run build
```

## Archivos de control

- `global.json`: banda aprobada del SDK .NET.
- `Directory.Packages.props`: versiones NuGet centralizadas.
- `NuGet.Config`: única fuente NuGet autorizada.
- `.config/dotnet-tools.json`: herramienta local `dotnet-ef`.
- `.nvmrc` y `.node-version`: Node.js aprobado.
- `.npmrc` y `package.json`: npm, engines y versiones exactas.
- `packages.lock.json`: lockfile NuGet por proyecto.
- `package-lock.json`: se genera en la primera restauración local y luego se conserva.
