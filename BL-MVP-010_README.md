# BL-MVP-010 — Bootstrap de roles y extensiones PostgreSQL

**Fase:** F0 — Cimientos  
**Épica:** EP-01 — Datos, persistencia e integración  
**Tipo:** Habilitador  
**Traza:** DDC; SEG; DAT  
**SP:** 5  
**Dependencias:** BL-MVP-006 y BL-MVP-009

Resultado aceptable:

> La instalación crea roles NOLOGIN, revoca privilegios públicos e instala extensiones autorizadas de forma reproducible.

## Aplicación

Extraiga el ZIP sobre la raíz del repositorio y reemplace archivos.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-010.ps1
```

El script:

1. valida Docker Compose;
2. ejecuta el control de secretos de BL-MVP-009;
3. aplica el bootstrap a la base local existente;
4. lo ejecuta una segunda vez para demostrar idempotencia;
5. verifica roles, extensiones y privilegios;
6. formatea y ejecuta la puerta de calidad.

Después:

```powershell
.\scripts\local\start.ps1
.\scripts\local\verify-running.ps1
.\scripts\database\verify-bootstrap.ps1
```

No haga commit hasta que las verificaciones terminen correctamente.
