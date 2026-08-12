# Instalación BL-MVP-041

Base requerida: `c6ee8afcb1acbc56654294a9b9fcd3e183b0973c`.

1. Extraer el ZIP sobre la raíz de `SistemaMusicaYAprender`.
2. Desde PowerShell en la raíz:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-041.ps1
```

3. No ejecutar `git add`, commit ni push durante la instalación.
4. Compartir la salida completa para revisar GREEN local e inventario antes de staging.

El instalador valida HEAD, inventario, calidad completa, build Release, acceso mínimo y el smoke real de proyección pública. No modifica el SQL maestro ni crea una migración nueva.
