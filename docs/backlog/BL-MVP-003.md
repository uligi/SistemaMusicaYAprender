# BL-MVP-003 - Definir reglas de código, análisis estático y formato

- Tipo: Habilitador
- Fase: F0 - Cimientos
- Épica: EP-00 - Ingeniería y repositorio
- SP: 3
- Dependencias: BL-MVP-001, BL-MVP-002
- Traza: MAN; SEG

## Resultado esperado

La compilación falla ante errores de análisis acordados y el formato es reproducible en frontend, backend y SQL.

## Implementado

- Analizadores .NET y warnings como errores.
- Estilo C# integrado al build y verificación mediante `dotnet format`.
- TypeScript estricto con controles adicionales de seguridad de tipos.
- Prettier central para frontend, configuración, documentación y SQL PostgreSQL.
- Scripts de formato y puerta de calidad en PowerShell/Bash.
- `npm.cmd` en scripts de Windows para evitar bloqueos de `npm.ps1` por ExecutionPolicy.
- Convención formal de categorización de carpetas.
- Reorganización de los pocos archivos existentes en categorías semánticas sin alterar los proyectos.

## Evidencia local esperada

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\format-code.ps1
.\scripts\check-quality.ps1
```

`check-quality.ps1` debe terminar con `OK: puerta local BL-MVP-003 aprobada.`
