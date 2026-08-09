# BL-MVP-011 — SQL maestro como migración inicial embebida

## Aplicación

Extraiga este ZIP sobre la raíz del repositorio y reemplace archivos.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-011.ps1
```

El script crea una base temporal PostgreSQL 18 completamente vacía, aplica BL-MVP-010, ejecuta `InitialPhysicalSchema` desde recursos embebidos y verifica la línea base.

Después:

```powershell
.\scripts\local\start.ps1
.\scripts\local\verify-running.ps1
.\scripts\database\verify-physical-schema.ps1
```

No haga commit antes de completar estas verificaciones.
