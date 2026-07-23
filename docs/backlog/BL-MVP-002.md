# BL-MVP-002 — Fijar SDK, runtime, gestores y lockfiles

## Tipo
Habilitador · EP-00 · F0 · 3 SP · depende de BL-MVP-001.

## Resultado aceptable adaptado al entorno
La restauración local y de CI utiliza versiones aprobadas y reproducibles compatibles con Visual Studio 2022:

- .NET SDK 9.0, banda 9.0.3xx, último parche instalado.
- Destino `net9.0` y C# 13.
- EF Core 9.0.18, Npgsql EF Core 9.0.4 y Npgsql 9.0.5.
- Node.js 24.18.0 LTS y npm 11.16.0.
- React/React DOM 19.2.7, TypeScript 7.0.2 y Vite 8.1.5.
- Versiones NuGet centralizadas en `Directory.Packages.props`.
- Paquetes npm sin rangos flotantes y `package-lock.json` obligatorio.
- `packages.lock.json` por proyecto y restauración bloqueada en CI.
- Herramienta local `dotnet-ef` 9.0.18.

## Evidencia

1. `dotnet --version` devuelve una versión `9.0.3xx`.
2. `dotnet restore --locked-mode` finaliza sin modificar lockfiles.
3. `dotnet tool restore` instala `dotnet-ef` 9.0.18.
4. `node --version` devuelve `v24.18.0`.
5. `npm --version` devuelve `11.16.0`.
6. `npm ci` no modifica `package-lock.json`.
7. `npm run build` y `dotnet build --no-restore` finalizan correctamente.

## Advertencia de ciclo de vida
.NET 9 permanece soportado hasta el 10 de noviembre de 2026. El proyecto debe migrar a .NET 10 LTS y a una versión de Visual Studio compatible antes de esa fecha. Esta adaptación no cambia la arquitectura modular ni el modelo de datos.
