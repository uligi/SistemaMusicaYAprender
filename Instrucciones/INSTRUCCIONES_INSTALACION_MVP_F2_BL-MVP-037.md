# Instalación BL-MVP-037

Base requerida:

`95140c4fbc41a0bd06fca638b441db5932501c92`

Desde:

`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

Extraer `BL-MVP-037_Paquete_Instalacion.zip` directamente sobre la raíz del repositorio y ejecutar:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-037.ps1
```

El instalador exige `main`, HEAD exacto, índice sin staging y ausencia de cambios ajenos al paquete. Luego aplica únicamente los tres parches tracked necesarios (`Program.cs`, `EditorialArea.tsx`, `ci.yml`), restaura la salida incremental TypeScript rastreada, ejecuta la puerta completa y finalmente el smoke real de BL-MVP-037.

No ejecutar `git add`, commit ni push hasta obtener GREEN local y revisar el inventario final.

El script no modifica el SQL maestro ni ejecuta una migración de producción.
