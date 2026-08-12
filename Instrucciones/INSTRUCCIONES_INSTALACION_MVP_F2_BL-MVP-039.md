# Instalación BL-MVP-039

1. Confirma que `main` está en `e0fd70dbfb5d120c782a3645ce81ab2795917b2b`.
2. El índice Git debe estar vacío.
3. Extrae el ZIP directamente sobre la raíz del repositorio.
4. Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-039.ps1
```

El instalador aplica cambios controlados, ejecuta la puerta de calidad y el smoke BL-MVP-039. No ejecuta `git add`, commit, push ni una migración de producción.

No hagas staging hasta revisar el inventario final.
