# Instalación BL-MVP-033

Base requerida: `51c49e039e5b244dd8b4f2b27254ed4899bdc1b4`, rama `main`.

Extraiga `BL-MVP-033_Paquete_Instalacion.zip` directamente sobre la raíz del repositorio, sin carpeta envolvente.

Desde PowerShell:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-033.ps1
```

El instalador no ejecuta `git add`, commit ni push. Los archivos no rastreados que ya existían fuera del paquete se preservan y deben continuar fuera del staging.

Cierre local esperado:

```text
OK: BL-MVP-033 instalado y validado localmente con auditoría primaria protegida.
No se ejecuto git add, commit ni push.
```
