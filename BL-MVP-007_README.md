# BL-MVP-007 — Readiness, liveness y dependencias

**Fase:** F0 — Cimientos  
**Épica:** EP-00 — Ingeniería y repositorio  
**Tipo:** Habilitador  
**Traza:** DIS; OBS; RNF-MVP-026-037  
**SP:** 3  
**Dependencia:** BL-MVP-006

Resultado aceptable de la línea base: los endpoints distinguen proceso vivo,
servicio listo y dependencia degradada sin revelar secretos.

## Aplicación

Copie el contenido del ZIP sobre la raíz del repositorio y reemplace archivos.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-007.ps1
```

Cuando termine correctamente:

```powershell
.\scripts\local\start.ps1
.\scripts\local\verify-running.ps1
.\scripts\local\verify-health-degradation.ps1
```

No haga commit hasta que las tres verificaciones terminen correctamente.
