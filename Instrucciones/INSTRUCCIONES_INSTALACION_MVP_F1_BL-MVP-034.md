# Instalación BL-MVP-034

Base requerida: `8d143e2cb10b89537fb8be2763decc609237ea16`, rama `main`.

Extraiga `BL-MVP-034_Paquete_Instalacion.zip` directamente sobre la raíz del repositorio.

Desde PowerShell:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-034.ps1
```

El instalador valida la toolchain congelada, calidad completa, entorno local, regresiones BL030–BL033 y el smoke real de BL034. Restaura `apps/web/tsconfig.app.tsbuildinfo` si TypeScript lo modifica.

No ejecuta `git add`, commit ni push.
