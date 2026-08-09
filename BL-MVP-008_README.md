# BL-MVP-008 — Instrumentar OpenTelemetry y correlación

**Fase:** F0 — Cimientos  
**Épica:** EP-00 — Ingeniería y repositorio  
**Tipo:** Habilitador  
**Traza:** OBS; RNF-MVP-120-131  
**SP:** 5  
**Dependencias:** BL-MVP-004 y BL-MVP-006

Resultado: API, worker y cliente emiten trazas, métricas y logs correlacionados con
datos mínimos y nombres versionados.

## Aplicación

Extraiga el ZIP sobre la raíz del repositorio y reemplace archivos.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-008.ps1
```

El script instala las dependencias OpenTelemetry del cliente, actualiza los
lockfiles .NET, valida Compose, formatea y ejecuta la puerta de calidad.

Después:

```powershell
.\scripts\local\start.ps1
.\scripts\local\verify-running.ps1
.\scripts\local\verify-telemetry.ps1
```

La última prueba solicita abrir `http://localhost:5173` al menos 10 segundos
porque el JavaScript del navegador debe ejecutarse para emitir sus propias señales.

No haga commit hasta que `verify-telemetry.ps1` termine en `OK`.
