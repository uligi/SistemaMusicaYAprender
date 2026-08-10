# BL-MVP-024C — selección determinista de Git Bash

## Motivo

La tercera ejecución de `scripts/apply-bl-mvp-024.ps1` aprobó la puerta local de calidad, las cinco pruebas E2E y el arranque saludable de los siete servicios, pero el smoke API/PostgreSQL no comenzó. PowerShell resolvió primero `C:\Windows\System32\bash.exe`, que delegó en una distribución WSL sin `/bin/bash`.

## Corrección

`Resolve-GitBash` deriva ahora `bash.exe` desde la instalación de `git.exe` antes de ejecutar el verificador. Esto evita el alias de WSL y conserva el mismo script Bash usado por CI.

El correctivo no cambia la aplicación, la API, PostgreSQL, migraciones, consentimientos ni pruebas.

## Aplicación

Extraer este ZIP directamente en la raíz del repositorio, aceptar la sobrescritura de `scripts/apply-bl-mvp-024.ps1` y ejecutar nuevamente:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-024.ps1
```

No usar opciones `Skip` ni ejecutar `git add`, commit o push antes del cierre GREEN.
