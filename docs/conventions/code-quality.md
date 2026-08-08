# Convenciones de calidad de código

## Objetivo

BL-MVP-003 convierte las reglas de estilo y análisis en verificaciones reproducibles. Un cambio no se considera limpio solo porque compile: debe respetar análisis estático, formato y límites de módulo.

## Backend .NET

- C# 13 sobre `net9.0` mientras Visual Studio actual no soporte el destino original .NET 10.
- Nullable habilitado.
- Analizadores .NET en nivel `9.0-recommended`.
- Reglas de estilo durante build.
- Todos los warnings de compilación/análisis se tratan como errores.
- `dotnet format` es la autoridad de formato C#.
- Los namespaces siguen la ubicación conceptual del archivo, pero una carpeta no obliga a crear capas artificiales.

## Frontend

- TypeScript `strict` y comprobaciones adicionales: índices, opcionales exactos, overrides, switch y símbolos sin uso.
- TypeScript es el analizador estático principal en BL-MVP-003.
- Prettier es la autoridad de formato para TypeScript, TSX, CSS, HTML, JSON, Markdown y YAML.
- No se incorpora `typescript-eslint` en esta línea base porque la versión actualmente fijada de TypeScript 7 queda fuera de su rango oficial de soporte. Se reevaluará al actualizar la herramienta o el compilador.

## SQL PostgreSQL

- Prettier + `prettier-plugin-sql` formatea archivos `.sql` con dialecto PostgreSQL.
- Sangría SQL: 4 espacios.
- La validación semántica del DDL y las restricciones de PostgreSQL pertenece a los PBI de datos posteriores; BL-MVP-003 solo fija el formato reproducible.

## Comandos

Aplicar formato:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\format-code.ps1
```

Comprobar todo sin modificar archivos:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\check-quality.ps1
```

La puerta local valida toolchain, restauración, TypeScript, Prettier, build .NET, `dotnet format` y límites de módulos.
