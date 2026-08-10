# BL-MVP-010A — Limpieza del mensaje de Quality Gate

Este parche elimina el texto heredado:

`OK: puerta local BL-MVP-009 aprobada.`

y lo reemplaza por un mensaje genérico:

`OK: puerta local de calidad aprobada.`

No cambia ninguna validación ni comportamiento funcional.

## Aplicación

```powershell
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-010a.ps1
```

Si termina en `OK`, el repositorio queda listo para commit/push de BL-MVP-010.
