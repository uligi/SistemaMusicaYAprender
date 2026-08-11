# Instalación — BL-MVP-032

Base publicada requerida:

`c21dd7b6688e60390d437f91695dda6a32639645`

Rama requerida: `main`.

Extrae `BL-MVP-032_Paquete_Instalacion.zip` directamente sobre la raíz del repositorio.

El paquete usa:

```text
Instrucciones/
README/
scripts/
```

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-032.ps1
```

La puerta aplica cambios acotados sobre la base publicada, ejecuta calidad completa, levanta el
entorno local, ejecuta la regresión BL-MVP-031 y el smoke real de MFA.

No usar `Skip*`. No ejecutar `git add`, commit ni push hasta GREEN local completo y revisión de
inventario.
